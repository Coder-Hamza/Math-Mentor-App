"""Gemini (Google AI Studio, free tier) client for the tutor.

* The network call is injectable (``generate=``) so tests never hit the real API.
* All failures are mapped to ``AIServiceError`` subclasses — callers never see SDK errors.
* Only transient failures (5xx / network) are retried; quota and auth errors are not.
* The prompt is built from ``TutorPrompt`` (no personal fields) and free text is PII-scrubbed.
"""

import asyncio
import json
import logging
import re
from collections.abc import Awaitable, Callable, Sequence
from dataclasses import dataclass
from functools import lru_cache
from typing import Any, Final

import httpx
from google import genai
from google.genai import errors as genai_errors
from google.genai import types
from pydantic import ValidationError

from app.core.config import Settings, get_settings
from app.schemas.ai_schemas import GeminiTutorAnswer, Language
from app.services.ai.errors import (
    AIBadResponseError,
    AIModelUnavailableError,
    AINotConfiguredError,
    AIQuotaExceededError,
    AIServiceError,
    AITimeoutError,
    AIUnavailableError,
)
from app.services.ai.privacy import scrub_pii
from app.services.ai.prompts import DEFAULT_STUDENT_LEVEL, SYSTEM_PROMPT, TutorPrompt, build_prompt
from app.services.ai.rate_limiter import RateLimiter

logger = logging.getLogger(__name__)

GenerateFn = Callable[..., Awaitable[Any]]

MAX_FALLBACK_LENGTH: Final = 6000
_CODE_FENCE: Final = re.compile(r"^\s*```(?:json)?\s*(.*?)\s*```\s*$", re.DOTALL)


@dataclass(frozen=True)
class GeminiResult:
    answer: GeminiTutorAnswer
    structured: bool  # False => Gemini ignored the JSON format; ``answer`` wraps raw text
    model: str = ""  # which model actually answered (primary or fallback)


class _ModelNotFoundError(Exception):
    """HTTP 404 for a model name: retired or not available to this key. Internal only."""


def parse_answer(text: str) -> GeminiResult:
    """Parse Gemini's JSON. Never raises: unusable JSON degrades to a plain-text answer."""
    stripped = text.strip()
    fenced = _CODE_FENCE.match(stripped)
    candidates = [fenced.group(1) if fenced else stripped]
    start, end = stripped.find("{"), stripped.rfind("}")
    if 0 <= start < end:
        candidates.append(stripped[start : end + 1])
    for candidate in candidates:
        try:
            return GeminiResult(GeminiTutorAnswer.model_validate_json(candidate), structured=True)
        except ValidationError:
            continue
    logger.warning("Gemini response was not valid tutor JSON; using plain-text fallback")
    explanation = stripped[:MAX_FALLBACK_LENGTH]
    return GeminiResult(GeminiTutorAnswer(explanation=explanation), structured=False)


def _map_api_error(exc: genai_errors.APIError) -> AIServiceError:
    code = exc.code
    if code == 429:
        logger.warning("Gemini quota exhausted (HTTP 429 from Google)")
        return AIQuotaExceededError(60)
    if code in (401, 403):
        logger.error("Gemini rejected the API key (HTTP %s) — check GEMINI_API_KEY", code)
        return AINotConfiguredError()
    logger.error("Gemini API error HTTP %s: %s", code, _detail(exc))
    return AIUnavailableError()


def _detail(exc: genai_errors.APIError) -> str:
    """Google's error message (never contains user data), truncated for logs."""
    return str(getattr(exc, "message", "") or "")[:300]


def _is_transient(exc: Exception) -> bool:
    if isinstance(exc, genai_errors.APIError):
        return exc.code >= 500
    return isinstance(exc, httpx.TransportError | OSError)


class GeminiService:
    def __init__(
        self,
        settings: Settings,
        *,
        generate: GenerateFn | None = None,
        rate_limiter: RateLimiter | None = None,
        sleep: Callable[[float], Awaitable[None]] = asyncio.sleep,
    ) -> None:
        self._settings = settings
        self._generate = generate
        self._limiter = rate_limiter or RateLimiter(
            settings.gemini_rate_limit_per_minute, settings.gemini_rate_limit_per_day
        )
        self._sleep = sleep
        # Models that returned 404 in this process; skipped so we don't spend quota on them.
        self._unavailable_models: set[str] = set()

    @property
    def models(self) -> list[str]:
        """Primary first, then the fallback (if configured and different)."""
        primary, fallback = self._settings.gemini_model, self._settings.gemini_fallback_model
        return [primary] + ([fallback] if fallback and fallback != primary else [])

    def _get_generate(self) -> GenerateFn:
        if self._generate is None:
            key = self._settings.gemini_api_key
            if key is None or not key.get_secret_value().strip():
                raise AINotConfiguredError()
            client = genai.Client(api_key=key.get_secret_value())
            self._generate = client.aio.models.generate_content
        return self._generate

    def _config(self) -> types.GenerateContentConfig:
        return types.GenerateContentConfig(
            system_instruction=SYSTEM_PROMPT,
            response_mime_type="application/json",
            response_schema=GeminiTutorAnswer,
            temperature=0.3,
        )

    async def ask_tutor(
        self,
        *,
        question: str,
        topic: str,
        unit: str,
        student_level: str = DEFAULT_STUDENT_LEVEL,
        language: Language = Language.URDU_ENGLISH,
        reference_formulas: Sequence[str] = (),
    ) -> GeminiResult:
        prompt = TutorPrompt(
            question=scrub_pii(question),
            topic=topic,
            unit=unit,
            student_level=student_level,
            language=language,
            reference_formulas=tuple(reference_formulas),
        )
        model, text = await self._call(build_prompt(prompt))
        result = parse_answer(text)
        return GeminiResult(result.answer, result.structured, model)

    async def _call(self, contents: str) -> tuple[str, str]:
        """Try each model in order; only a 404 (model unavailable) moves on to the next."""
        generate = self._get_generate()
        config = self._config()
        candidates = [m for m in self.models if m not in self._unavailable_models]
        for model in candidates or self.models:  # all marked unavailable -> probe them again
            try:
                return model, await self._call_model(generate, model, contents, config)
            except _ModelNotFoundError:
                self._unavailable_models.add(model)
        logger.error("No configured Gemini model is available: %s", ", ".join(self.models))
        raise AIModelUnavailableError()

    async def _call_model(
        self, generate: GenerateFn, model: str, contents: str, config: types.GenerateContentConfig
    ) -> str:
        attempts = self._settings.gemini_max_retries + 1
        for attempt in range(1, attempts + 1):
            self._limiter.acquire()
            try:
                async with asyncio.timeout(self._settings.gemini_timeout_seconds):
                    response = await generate(model=model, contents=contents, config=config)
            except TimeoutError:
                logger.warning("Gemini call timed out (attempt %d/%d)", attempt, attempts)
                raise AITimeoutError() from None
            except (genai_errors.APIError, httpx.TransportError, OSError) as exc:
                if isinstance(exc, genai_errors.APIError) and exc.code == 404:
                    logger.error("Gemini model %r unavailable (HTTP 404): %s", model, _detail(exc))
                    raise _ModelNotFoundError(model) from exc
                if _is_transient(exc) and attempt < attempts:
                    logger.warning("Transient Gemini error, retrying (%d/%d)", attempt, attempts)
                    await self._sleep(0.5 * 2 ** (attempt - 1))
                    continue
                if isinstance(exc, genai_errors.APIError):
                    raise _map_api_error(exc) from exc
                logger.error("Gemini unreachable: %s", type(exc).__name__)
                raise AIUnavailableError() from exc
            text = getattr(response, "text", None)
            if not isinstance(text, str) or not text.strip():
                raise AIBadResponseError()
            return text
        raise AIUnavailableError()  # pragma: no cover  (loop always returns or raises)


@lru_cache
def get_gemini_service() -> GeminiService:
    """Process-wide service (shares one client and one rate limiter)."""
    return GeminiService(get_settings())


def describe_answer(result: GeminiResult) -> str:
    """Compact, PII-free summary for logs."""
    a = result.answer
    return json.dumps(
        {
            "model": result.model,
            "structured": result.structured,
            "steps": len(a.steps),
            "checks": len(a.checks),
        }
    )
