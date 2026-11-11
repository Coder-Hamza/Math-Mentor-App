"""Gemini (Google AI Studio, free tier) client for the tutor.

* The network call is injectable (``generate=``) so tests never hit the real API.
* All failures are mapped to ``AIServiceError`` subclasses — callers never see SDK errors.
* Only transient failures (5xx / network) are retried on the same model.
* Model fallback: a 404 (model unavailable) or 429 (that model's quota used up) on the primary
  moves on to ``GEMINI_FALLBACK_MODEL``. 429'd models cool down (Google's retryDelay, else
  60 s); 404'd models are skipped for the rest of the process.
* The local ``RateLimiter`` is app-wide (all models together) and never triggers fallback.
* The prompt is built from ``TutorPrompt`` (no personal fields) and free text is PII-scrubbed.
"""

import asyncio
import json
import logging
import math
import re
import time
from collections.abc import Awaitable, Callable, Sequence
from dataclasses import dataclass
from functools import lru_cache
from typing import Any, Final

import httpx
from google import genai
from google.genai import errors as genai_errors
from google.genai import types
from pydantic import BaseModel, ValidationError

from app.core.config import Settings, get_settings
from app.schemas.ai_schemas import GeminiTutorAnswer, Language
from app.schemas.solver_schemas import GeminiSolverAnswer
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
from app.services.ai.solver_prompts import (
    SOLVER_SYSTEM_PROMPT,
    SolverPrompt,
    build_solver_prompt,
)

logger = logging.getLogger(__name__)

GenerateFn = Callable[..., Awaitable[Any]]

MAX_FALLBACK_LENGTH: Final = 6000
_CODE_FENCE: Final = re.compile(r"^\s*```(?:json)?\s*(.*?)\s*```\s*$", re.DOTALL)


@dataclass(frozen=True)
class GeminiResult:
    answer: GeminiTutorAnswer
    structured: bool  # False => Gemini ignored the JSON format; ``answer`` wraps raw text
    model: str = ""  # which model actually answered (primary or fallback)


@dataclass(frozen=True)
class SolverGeminiResult:
    answer: GeminiSolverAnswer | None  # None => not valid solver JSON; see ``raw_text``
    raw_text: str
    model: str = ""

    @property
    def structured(self) -> bool:
        return self.answer is not None


class _ModelNotFoundError(Exception):
    """HTTP 404 for a model name: retired or not available to this key. Internal only."""


class _ModelQuotaError(Exception):
    """HTTP 429 for one model (its free-tier quota is used up). Internal only."""

    def __init__(self, retry_after: int) -> None:
        super().__init__(retry_after)
        self.retry_after = retry_after


DEFAULT_QUOTA_COOLDOWN: Final = 60
_RETRY_DELAY: Final = re.compile(r"^\s*(\d+(?:\.\d+)?)s\s*$")


def _retry_after_seconds(exc: genai_errors.APIError) -> int:
    """Read Google's ``RetryInfo.retryDelay`` (e.g. ``"37s"``); default 60 s."""
    error = exc.details.get("error", {}) if isinstance(exc.details, dict) else {}
    for detail in error.get("details", []) if isinstance(error, dict) else []:
        delay = detail.get("retryDelay") if isinstance(detail, dict) else None
        if isinstance(delay, str) and (match := _RETRY_DELAY.match(delay)):
            return max(1, math.ceil(float(match.group(1))))
    return DEFAULT_QUOTA_COOLDOWN


def parse_answer(text: str) -> GeminiResult:
    """Parse Gemini's JSON. Never raises: unusable JSON degrades to a plain-text answer."""
    stripped = text.strip()
    for candidate in _json_candidates(stripped):
        try:
            return GeminiResult(GeminiTutorAnswer.model_validate_json(candidate), structured=True)
        except ValidationError:
            continue
    logger.warning("Gemini response was not valid tutor JSON; using plain-text fallback")
    explanation = stripped[:MAX_FALLBACK_LENGTH]
    return GeminiResult(GeminiTutorAnswer(explanation=explanation), structured=False)


def _json_candidates(text: str) -> list[str]:
    stripped = text.strip()
    fenced = _CODE_FENCE.match(stripped)
    candidates = [fenced.group(1) if fenced else stripped]
    start, end = stripped.find("{"), stripped.rfind("}")
    if 0 <= start < end:
        candidates.append(stripped[start : end + 1])
    return candidates


def parse_solver_answer(text: str) -> SolverGeminiResult:
    """Parse the solver JSON. Never raises: unusable JSON keeps the raw text."""
    for candidate in _json_candidates(text):
        try:
            return SolverGeminiResult(GeminiSolverAnswer.model_validate_json(candidate), text)
        except ValidationError:
            continue
    logger.warning("Gemini response was not valid solver JSON; using plain-text fallback")
    return SolverGeminiResult(None, text.strip()[:MAX_FALLBACK_LENGTH])


def _map_api_error(exc: genai_errors.APIError) -> AIServiceError:
    code = exc.code
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
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self._settings = settings
        self._generate = generate
        self._limiter = rate_limiter or RateLimiter(
            settings.gemini_rate_limit_per_minute, settings.gemini_rate_limit_per_day
        )
        self._sleep = sleep
        self._clock = clock
        # Models that returned 404 in this process; skipped so we don't spend quota on them.
        self._unavailable_models: set[str] = set()
        # Models that returned 429, mapped to the monotonic time their cooldown ends.
        self._quota_cooldown_until: dict[str, float] = {}

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

    def _config(
        self,
        system_instruction: str = SYSTEM_PROMPT,
        schema: type[BaseModel] = GeminiTutorAnswer,
    ) -> types.GenerateContentConfig:
        return types.GenerateContentConfig(
            system_instruction=system_instruction,
            response_mime_type="application/json",
            response_schema=schema,
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

    async def solve_question(
        self,
        *,
        chapter: str,
        question: str,
        book_answer: str | None = None,
        grade_level: str = "HSC-I",
        language: Language = Language.URDU_ENGLISH,
    ) -> SolverGeminiResult:
        """Full textbook-pattern solution. Each attempt may take up to the solver's Gemini
        budget (complex questions need longer than tutor answers)."""
        prompt = SolverPrompt(
            chapter=scrub_pii(chapter),
            question=scrub_pii(question),
            book_answer=scrub_pii(book_answer) if book_answer else None,
            grade_level=grade_level,
            language=language,
        )
        model, text = await self._call(
            build_solver_prompt(prompt),
            config=self._config(SOLVER_SYSTEM_PROMPT, GeminiSolverAnswer),
            attempt_seconds=self._settings.solver_gemini_budget_seconds,
        )
        result = parse_solver_answer(text)
        return SolverGeminiResult(result.answer, result.raw_text, model)

    async def _call(
        self,
        contents: str,
        *,
        config: types.GenerateContentConfig | None = None,
        attempt_seconds: float | None = None,
    ) -> tuple[str, str]:
        """Try each model in order. 404 (model unavailable) or 429 (model quota used up)
        moves on to the next model; every other error is final."""
        generate = self._get_generate()
        config = config or self._config()
        attempt_seconds = attempt_seconds or self._settings.gemini_timeout_seconds
        candidates = self._candidates()
        quota_waits: list[int] = []
        for model in candidates:
            try:
                return model, await self._call_model(
                    generate, model, contents, config, attempt_seconds
                )
            except _ModelNotFoundError:
                self._unavailable_models.add(model)
            except _ModelQuotaError as exc:
                self._quota_cooldown_until[model] = self._clock() + exc.retry_after
                quota_waits.append(exc.retry_after)
                logger.warning(
                    "Gemini model %r hit its quota (HTTP 429); skipping it for %ds",
                    model,
                    exc.retry_after,
                )
        if quota_waits:
            raise AIQuotaExceededError(min(quota_waits))
        logger.error("No configured Gemini model is available: %s", ", ".join(self.models))
        raise AIModelUnavailableError()

    def _candidates(self) -> list[str]:
        """Models worth calling now, in priority order.

        404'd models are skipped (all 404'd -> probe them all again). Models cooling down
        after a 429 are skipped; if every model is cooling down we fail fast without
        spending a request.
        """
        usable = [m for m in self.models if m not in self._unavailable_models] or self.models
        now = self._clock()
        ready = [m for m in usable if self._quota_cooldown_until.get(m, 0.0) <= now]
        if not ready:
            wait = min(self._quota_cooldown_until[m] for m in usable) - now
            logger.warning("All Gemini models are cooling down after quota errors")
            raise AIQuotaExceededError(max(1, math.ceil(wait)))
        return ready

    async def _call_model(
        self,
        generate: GenerateFn,
        model: str,
        contents: str,
        config: types.GenerateContentConfig,
        attempt_seconds: float,
    ) -> str:
        attempts = self._settings.gemini_max_retries + 1
        for attempt in range(1, attempts + 1):
            self._limiter.acquire()
            try:
                async with asyncio.timeout(attempt_seconds):
                    response = await generate(model=model, contents=contents, config=config)
            except TimeoutError:
                logger.warning("Gemini call timed out (attempt %d/%d)", attempt, attempts)
                raise AITimeoutError() from None
            except (genai_errors.APIError, httpx.TransportError, OSError) as exc:
                if isinstance(exc, genai_errors.APIError) and exc.code == 404:
                    logger.error("Gemini model %r unavailable (HTTP 404): %s", model, _detail(exc))
                    raise _ModelNotFoundError(model) from exc
                if isinstance(exc, genai_errors.APIError) and exc.code == 429:
                    raise _ModelQuotaError(_retry_after_seconds(exc)) from exc
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
