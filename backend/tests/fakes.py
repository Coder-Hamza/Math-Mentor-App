"""Test doubles for Gemini. The real API is NEVER called from tests."""

import asyncio
import json
from types import SimpleNamespace
from typing import Any

from google.genai import errors as genai_errors

from app.core.config import Settings, get_settings
from app.services.ai.gemini_service import GeminiService
from app.services.ai.rate_limiter import RateLimiter

GOOD_ANSWER: dict[str, Any] = {
    "explanation": "Hum double-angle formula use karenge. Final answer: sin 2x = 2 sin x cos x.",
    "steps": [
        "Step 1: sin(A + B) = sin A cos B + cos A sin B likhein.",
        "Step 2: A = B = x rakhein.",
        "Step 3: sin 2x = 2 sin x cos x. Shabash!",
    ],
    "formulas_used": ["Sine of a sum: sin(A+B) = sinA cosB + cosA sinB"],
    "checks": [
        {"lhs": "sin(2*x)", "rhs": "2*sin(x)*cos(x)"},
        {"lhs": "sin(x + y)", "rhs": "sin(x)*cos(y) + cos(x)*sin(y)"},
    ],
}


def answer_json(**overrides: Any) -> str:
    return json.dumps(GOOD_ANSWER | overrides)


def api_error(code: int, *, retry_delay: str | None = None) -> genai_errors.APIError:
    error: dict[str, Any] = {"code": code, "message": "simulated", "status": "SIMULATED"}
    if retry_delay is not None:
        error["details"] = [
            {"@type": "type.googleapis.com/google.rpc.RetryInfo", "retryDelay": retry_delay}
        ]
    payload = {"error": error}
    cls = genai_errors.ClientError if code < 500 else genai_errors.ServerError
    return cls(code, payload)


class FakeGenerate:
    """Stands in for ``client.aio.models.generate_content``.

    Each outcome is used once in order (the last one repeats): a ``str`` becomes the response
    text, an exception is raised, ``None`` gives a response without text, and a float sleeps
    that many seconds (to simulate a hang).
    """

    def __init__(self, *outcomes: object) -> None:
        self.outcomes = list(outcomes) or [answer_json()]
        self.calls: list[dict[str, Any]] = []

    async def __call__(self, *, model: str, contents: str, config: Any) -> Any:
        self.calls.append({"model": model, "contents": contents, "config": config})
        outcome = self.outcomes.pop(0) if len(self.outcomes) > 1 else self.outcomes[0]
        if isinstance(outcome, BaseException):
            raise outcome
        if isinstance(outcome, float):
            await asyncio.sleep(outcome)
            return SimpleNamespace(text=answer_json())
        return SimpleNamespace(text=outcome)

    def sent_text(self) -> str:
        """Everything that was sent to 'Gemini' (prompts + system instructions)."""
        return "\n".join(
            f"{call['contents']}\n{call['config'].system_instruction}" for call in self.calls
        )


async def no_sleep(_: float) -> None:
    return None


def make_settings(**overrides: Any) -> Settings:
    return get_settings().model_copy(update=overrides)


def make_gemini(
    generate: FakeGenerate,
    *,
    rate_limiter: RateLimiter | None = None,
    **settings_overrides: Any,
) -> GeminiService:
    return GeminiService(
        make_settings(**settings_overrides),
        generate=generate,
        rate_limiter=rate_limiter or RateLimiter(1000, 100_000),
        sleep=no_sleep,
    )


# ------------------------------------------------------------------ solver

GOOD_SOLUTION: dict[str, Any] = {
    "restated_question": "Quadratic equation x^2 - 5x + 6 = 0 ko hal karein.",
    "given": ["x^2 - 5x + 6 = 0"],
    "to_find": ["x ki values"],
    "steps": [
        {
            "title": "Factors talash karein",
            "explanation": "Hamein do numbers chahiye jinka product 6 aur sum -5 ho: -2 aur -3.",
            "formula_used": None,
            "calculation": "x^2 - 2x - 3x + 6 = 0",
        },
        {
            "title": "Factorise karein",
            "explanation": "Common factors bahar nikalein.",
            "formula_used": "Factorisation: ab = 0 => a = 0 or b = 0",
            "calculation": "(x - 2)(x - 3) = 0",
        },
        {
            "title": "Har factor ko zero rakhein",
            "explanation": "x - 2 = 0 ya x - 3 = 0.",
            "formula_used": None,
            "calculation": "x = 2, x = 3",
        },
    ],
    "method_used": "Factorisation Method",
    "formulas_applied": ["Zero product property: ab = 0 => a = 0 or b = 0"],
    "key_concepts": ["Quadratic equation", "Factorisation"],
    "final_answer": "x = 2, x = 3",
    "difficulty_level": "easy",
    "exam_tip": "Jawab ko wapas equation mein rakh kar zaroor check karein.",
    "checks": [
        {"lhs": "2**2 - 5*2 + 6", "rhs": "0"},
        {"lhs": "3**2 - 5*3 + 6", "rhs": "0"},
    ],
}


def solution_json(**overrides: Any) -> str:
    return json.dumps(GOOD_SOLUTION | overrides)
