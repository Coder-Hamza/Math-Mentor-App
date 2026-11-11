"""GeminiService with a fake transport: prompt building, parsing, errors, retries, privacy."""

import logging
from typing import Any

import httpx
import pytest
from google.genai import errors as genai_errors
from pydantic import SecretStr, ValidationError

from app.schemas.ai_schemas import GeminiTutorAnswer, Language
from app.services.ai import gemini_service as gemini_module
from app.services.ai.errors import (
    AIBadResponseError,
    AIModelUnavailableError,
    AINotConfiguredError,
    AIQuotaExceededError,
    AITimeoutError,
    AIUnavailableError,
)
from app.services.ai.gemini_service import GeminiResult, GeminiService, parse_answer
from app.services.ai.privacy import REDACTED, scrub_pii
from app.services.ai.prompts import SYSTEM_PROMPT, TutorPrompt, build_prompt
from app.services.ai.rate_limiter import RateLimiter
from tests.fakes import (
    GOOD_ANSWER,
    FakeGenerate,
    answer_json,
    api_error,
    make_gemini,
    make_settings,
    no_sleep,
)

ASK: dict[str, Any] = {
    "question": "Prove that sin 2x = 2 sin x cos x",
    "topic": "Double and Half Angle Identities",
    "unit": "Unit 10: Trigonometric Identities of Sum and Difference of Angles",
}


# ------------------------------------------------------------------ prompt building


def _prompt(**overrides: Any) -> str:
    return build_prompt(TutorPrompt(**(ASK | overrides)))


def test_prompt_contains_syllabus_context_and_question() -> None:
    text = _prompt(reference_formulas=("Sine of a double angle: sin(2*x) = 2*sin(x)*cos(x)",))
    assert "HSC-I (Class 11), Sindh Board, Pakistan" in text
    assert "Unit: Unit 10: Trigonometric Identities" in text
    assert "Topic: Double and Half Angle Identities" in text
    assert "Sine of a double angle: sin(2*x) = 2*sin(x)*cos(x)" in text
    assert ASK["question"] in text


def test_prompt_has_required_instructions() -> None:
    text = _prompt().lower()
    for phrase in ("step-by-step", "formulas", "encouraging", "explanation, steps, formulas_used"):
        assert phrase in text


@pytest.mark.parametrize(
    ("language", "phrase"),
    [(Language.URDU_ENGLISH, "mix of simple Urdu"), (Language.ENGLISH, "simple, clear English")],
)
def test_prompt_language_instruction(language: Language, phrase: str) -> None:
    assert phrase in _prompt(language=language)


def test_prompt_without_reference_formulas_omits_section() -> None:
    assert "Syllabus formulas" not in _prompt()


def test_system_prompt_defines_json_contract_and_audience() -> None:
    for phrase in (
        "HSC-I (Class 11)",
        "Sindh Board",
        "step by step",
        "encouraging",
        '"explanation"',
        '"steps"',
        '"formulas_used"',
        '"checks"',
        "SymPy syntax",
        "Never ask for or mention any personal information",
    ):
        assert phrase in SYSTEM_PROMPT


def test_tutor_prompt_cannot_carry_personal_fields() -> None:
    with pytest.raises(ValidationError):
        TutorPrompt.model_validate(ASK | {"student_name": "Ali"})
    assert not {"name", "email", "user_id", "student_name"} & set(TutorPrompt.model_fields)


# ------------------------------------------------------------------ PII scrubbing


@pytest.mark.parametrize(
    "pii",
    [
        "ali.khan@gmail.com",
        "03001234567",
        "0300-1234567",
        "+92 300 1234567",
        "00923001234567",
        "42101-1234567-1",
        "4210112345671",
    ],
)
def test_scrub_pii_removes_contact_details(pii: str) -> None:
    scrubbed = scrub_pii(f"My contact is {pii}, solve x^2 = 4")
    assert pii not in scrubbed
    assert REDACTED in scrubbed
    assert "solve x^2 = 4" in scrubbed


@pytest.mark.parametrize(
    "math", ["Find 3^12 = 531441", "Solve 2x + 3 = 7", "Evaluate 12345 * 6789", "Sum 1..100"]
)
def test_scrub_pii_leaves_math_alone(math: str) -> None:
    assert scrub_pii(math) == math


# ------------------------------------------------------------------ parse_answer


def test_parse_valid_json() -> None:
    result = parse_answer(answer_json())
    assert result.structured is True
    assert result.answer.steps == GOOD_ANSWER["steps"]
    assert len(result.answer.checks) == 2


def test_parse_json_in_code_fence() -> None:
    result = parse_answer(f"```json\n{answer_json()}\n```")
    assert result.structured is True


def test_parse_json_embedded_in_prose() -> None:
    result = parse_answer(f"Sure! Here it is:\n{answer_json()}\nGood luck!")
    assert result.structured is True


def test_parse_ignores_unknown_keys_and_defaults_missing_lists() -> None:
    result = parse_answer('{"explanation": "Only text", "extra": 1}')
    assert result.structured is True
    assert (result.answer.steps, result.answer.formulas_used, result.answer.checks) == ([], [], [])


@pytest.mark.parametrize(
    "text",
    [
        "Plain text answer without JSON",
        '{"explanation": ""}',  # empty explanation is invalid
        '{"steps": ["a"]}',  # missing explanation
        '{"explanation": "x", "steps": "not a list"}',
        "{not json}",
    ],
)
def test_invalid_json_falls_back_to_plain_text(text: str, caplog: pytest.LogCaptureFixture) -> None:
    with caplog.at_level(logging.WARNING):
        result = parse_answer(text)
    assert result.structured is False
    assert result.answer.explanation == text.strip()
    assert result.answer.checks == []
    assert "plain-text fallback" in caplog.text


def test_fallback_is_truncated() -> None:
    result = parse_answer("x" * 10_000)
    assert len(result.answer.explanation) == gemini_module.MAX_FALLBACK_LENGTH


# ------------------------------------------------------------------ ask_tutor happy path


async def test_ask_tutor_sends_prompt_and_config() -> None:
    fake = FakeGenerate(answer_json())
    service = make_gemini(fake, gemini_model="gemini-3.5-flash")

    result = await service.ask_tutor(**ASK, reference_formulas=["F: x = 1"])

    assert result.structured is True
    assert result.model == "gemini-3.5-flash"
    (call,) = fake.calls
    assert call["model"] == "gemini-3.5-flash"
    assert ASK["question"] in call["contents"]
    assert "- F: x = 1" in call["contents"]
    config = call["config"]
    assert config.system_instruction == SYSTEM_PROMPT
    assert config.response_mime_type == "application/json"
    assert config.response_schema is GeminiTutorAnswer


async def test_ask_tutor_scrubs_pii_from_question() -> None:
    fake = FakeGenerate()
    await make_gemini(fake).ask_tutor(
        **(ASK | {"question": "I am reachable at sana@example.com or 0321-7654321. Solve x+1=2"})
    )
    sent = fake.sent_text()
    assert "sana@example.com" not in sent
    assert "0321-7654321" not in sent
    assert "Solve x+1=2" in sent


async def test_non_json_reply_is_not_an_error() -> None:
    result = await make_gemini(FakeGenerate("Just some words")).ask_tutor(**ASK)
    assert result.structured is False
    assert result.answer.explanation == "Just some words"


@pytest.mark.parametrize("text", [None, "", "   "])
async def test_empty_reply_is_bad_response(text: str | None) -> None:
    with pytest.raises(AIBadResponseError) as info:
        await make_gemini(FakeGenerate(text)).ask_tutor(**ASK)  # type: ignore[arg-type]
    assert info.value.status_code == 502


# ------------------------------------------------------------------ errors and retries


async def test_quota_429_without_fallback_is_quota_error_and_not_retried(
    caplog: pytest.LogCaptureFixture,
) -> None:
    fake = FakeGenerate(api_error(429))
    service = make_gemini(fake, gemini_max_retries=2, gemini_fallback_model=None)
    with caplog.at_level(logging.WARNING), pytest.raises(AIQuotaExceededError) as info:
        await service.ask_tutor(**ASK)
    assert len(fake.calls) == 1  # quota errors are not retried on the same model
    assert info.value.status_code == 429
    assert info.value.headers["Retry-After"] == "60"
    assert "hit its quota (HTTP 429)" in caplog.text


@pytest.mark.parametrize("code", [401, 403])
async def test_rejected_key_maps_to_not_configured(code: int) -> None:
    with pytest.raises(AINotConfiguredError) as info:
        await make_gemini(FakeGenerate(api_error(code))).ask_tutor(**ASK)
    assert info.value.status_code == 503


# ------------------------------------------------------------------ model fallback (404)

PRIMARY, FALLBACK = "gemini-3.5-flash", "gemini-3.1-flash-lite"


def _fallback_service(fake: FakeGenerate, **overrides: Any) -> GeminiService:
    settings = {
        "gemini_model": PRIMARY,
        "gemini_fallback_model": FALLBACK,
        "gemini_max_retries": 2,
    } | overrides
    return make_gemini(fake, **settings)


async def test_primary_404_falls_back_to_secondary(caplog: pytest.LogCaptureFixture) -> None:
    """Seen for real: Google retired gemini-2.5-flash for new keys (HTTP 404)."""
    fake = FakeGenerate(api_error(404), answer_json())
    with caplog.at_level(logging.ERROR):
        result = await _fallback_service(fake).ask_tutor(**ASK)
    assert [c["model"] for c in fake.calls] == [PRIMARY, FALLBACK]  # 404 is not retried
    assert result.model == FALLBACK
    assert result.structured is True
    assert f"Gemini model '{PRIMARY}' unavailable (HTTP 404)" in caplog.text


async def test_unavailable_primary_is_skipped_on_later_requests() -> None:
    fake = FakeGenerate(api_error(404), answer_json())
    service = _fallback_service(fake)
    await service.ask_tutor(**ASK)
    await service.ask_tutor(**ASK)
    assert [c["model"] for c in fake.calls] == [PRIMARY, FALLBACK, FALLBACK]


async def test_both_models_404_is_503_model_unavailable(caplog: pytest.LogCaptureFixture) -> None:
    fake = FakeGenerate(api_error(404))
    with caplog.at_level(logging.ERROR), pytest.raises(AIModelUnavailableError) as info:
        await _fallback_service(fake).ask_tutor(**ASK)
    assert [c["model"] for c in fake.calls] == [PRIMARY, FALLBACK]
    assert (info.value.status_code, info.value.code) == (503, "ai_model_unavailable")
    assert "No configured Gemini model is available" in caplog.text


async def test_all_models_marked_unavailable_are_probed_again() -> None:
    fake = FakeGenerate(api_error(404), api_error(404), answer_json())
    service = _fallback_service(fake)
    with pytest.raises(AIModelUnavailableError):
        await service.ask_tutor(**ASK)
    result = await service.ask_tutor(**ASK)  # e.g. the key gained access again
    assert result.model == PRIMARY


@pytest.mark.parametrize("fallback", [None, "", PRIMARY])
async def test_without_distinct_fallback_only_primary_is_tried(fallback: str | None) -> None:
    fake = FakeGenerate(api_error(404))
    with pytest.raises(AIModelUnavailableError):
        await _fallback_service(fake, gemini_fallback_model=fallback).ask_tutor(**ASK)
    assert [c["model"] for c in fake.calls] == [PRIMARY]


@pytest.mark.parametrize(
    ("error", "expected"),
    [
        (api_error(401), AINotConfiguredError),
        (api_error(400), AIUnavailableError),
        (api_error(503), AIUnavailableError),
    ],
)
async def test_other_errors_do_not_trigger_fallback(
    error: Exception, expected: type[Exception]
) -> None:
    fake = FakeGenerate(error)
    with pytest.raises(expected):
        await _fallback_service(fake, gemini_max_retries=0).ask_tutor(**ASK)
    assert [c["model"] for c in fake.calls] == [PRIMARY]


def test_models_property_order() -> None:
    service = _fallback_service(FakeGenerate())
    assert service.models == [PRIMARY, FALLBACK]


# ------------------------------------------------------------------ quota fallback (429)


class FakeClock:
    def __init__(self) -> None:
        self.now = 1000.0

    def __call__(self) -> float:
        return self.now


def _quota_service(fake: FakeGenerate, clock: FakeClock, **overrides: Any) -> GeminiService:
    settings = {"gemini_model": PRIMARY, "gemini_fallback_model": FALLBACK} | overrides
    return GeminiService(
        make_settings(gemini_max_retries=2, **settings),
        generate=fake,
        rate_limiter=RateLimiter(1000, 100_000),
        sleep=no_sleep,
        clock=clock,
    )


async def test_primary_quota_429_falls_back(caplog: pytest.LogCaptureFixture) -> None:
    fake = FakeGenerate(api_error(429), answer_json())
    with caplog.at_level(logging.WARNING):
        result = await _quota_service(fake, FakeClock()).ask_tutor(**ASK)
    assert [c["model"] for c in fake.calls] == [PRIMARY, FALLBACK]  # 429 not retried on primary
    assert result.model == FALLBACK
    assert f"Gemini model '{PRIMARY}' hit its quota (HTTP 429); skipping it for 60s" in caplog.text


async def test_quota_cooldown_skips_primary_then_expires() -> None:
    clock = FakeClock()
    fake = FakeGenerate(api_error(429), answer_json())
    service = _quota_service(fake, clock)

    await service.ask_tutor(**ASK)  # primary 429 -> fallback
    clock.now += 59
    second = await service.ask_tutor(**ASK)  # still cooling down: straight to fallback
    clock.now += 2
    third = await service.ask_tutor(**ASK)  # cooldown over: primary again

    assert [c["model"] for c in fake.calls] == [PRIMARY, FALLBACK, FALLBACK, PRIMARY]
    assert (second.model, third.model) == (FALLBACK, PRIMARY)


async def test_google_retry_delay_sets_cooldown_and_retry_after() -> None:
    clock = FakeClock()
    fake = FakeGenerate(api_error(429, retry_delay="37.2s"))
    service = _quota_service(fake, clock)
    with pytest.raises(AIQuotaExceededError) as info:
        await service.ask_tutor(**ASK)
    assert info.value.headers["Retry-After"] == "38"
    assert [c["model"] for c in fake.calls] == [PRIMARY, FALLBACK]


async def test_both_models_on_quota_fail_fast_without_calling_google() -> None:
    clock = FakeClock()
    fake = FakeGenerate(api_error(429))
    service = _quota_service(fake, clock)
    with pytest.raises(AIQuotaExceededError):
        await service.ask_tutor(**ASK)
    calls_after_first = len(fake.calls)

    clock.now += 45
    with pytest.raises(AIQuotaExceededError) as info:
        await service.ask_tutor(**ASK)

    assert len(fake.calls) == calls_after_first == 2  # no request spent while cooling down
    assert info.value.headers["Retry-After"] == "15"


async def test_primary_404_and_fallback_429_reports_quota() -> None:
    fake = FakeGenerate(api_error(404), api_error(429))
    with pytest.raises(AIQuotaExceededError):
        await _quota_service(fake, FakeClock()).ask_tutor(**ASK)
    assert [c["model"] for c in fake.calls] == [PRIMARY, FALLBACK]


@pytest.mark.parametrize(
    ("details", "expected"),
    [
        ([{"@type": "type.googleapis.com/google.rpc.RetryInfo", "retryDelay": "12s"}], 12),
        ([{"retryDelay": "0.2s"}], 1),
        ([{"retryDelay": "soon"}], 60),
        (["not-a-dict"], 60),
        (None, 60),
    ],
)
def test_retry_after_parsing(details: object, expected: int) -> None:
    error: dict[str, object] = {"code": 429, "message": "q", "status": "RESOURCE_EXHAUSTED"}
    if details is not None:
        error["details"] = details
    exc = genai_errors.ClientError(429, {"error": error})
    assert gemini_module._retry_after_seconds(exc) == expected


def test_retry_after_parsing_with_non_dict_payload() -> None:
    exc = genai_errors.ClientError(429, ["unexpected", "list"])
    assert gemini_module._retry_after_seconds(exc) == 60


async def test_local_rate_limiter_does_not_trigger_fallback() -> None:
    fake = FakeGenerate()
    service = GeminiService(
        make_settings(gemini_model=PRIMARY, gemini_fallback_model=FALLBACK),
        generate=fake,
        rate_limiter=RateLimiter(per_minute=1, per_day=100),
        sleep=no_sleep,
    )
    await service.ask_tutor(**ASK)
    with pytest.raises(AIQuotaExceededError):
        await service.ask_tutor(**ASK)
    assert [c["model"] for c in fake.calls] == [PRIMARY]


async def test_other_client_error_maps_to_unavailable() -> None:
    fake = FakeGenerate(api_error(400))
    with pytest.raises(AIUnavailableError):
        await make_gemini(fake, gemini_max_retries=2).ask_tutor(**ASK)
    assert len(fake.calls) == 1


async def test_transient_server_error_is_retried_then_succeeds() -> None:
    fake = FakeGenerate(api_error(503), api_error(500), answer_json())
    result = await make_gemini(fake, gemini_max_retries=2).ask_tutor(**ASK)
    assert result.structured is True
    assert len(fake.calls) == 3


async def test_server_error_after_all_retries_is_unavailable() -> None:
    fake = FakeGenerate(api_error(503))
    with pytest.raises(AIUnavailableError) as info:
        await make_gemini(fake, gemini_max_retries=1).ask_tutor(**ASK)
    assert len(fake.calls) == 2
    assert info.value.status_code == 503


@pytest.mark.parametrize("error", [httpx.ConnectError("down"), ConnectionResetError("reset")])
async def test_network_errors_retry_then_unavailable(error: Exception) -> None:
    fake = FakeGenerate(error)
    with pytest.raises(AIUnavailableError):
        await make_gemini(fake, gemini_max_retries=1).ask_tutor(**ASK)
    assert len(fake.calls) == 2


async def test_retry_backoff_is_exponential() -> None:
    sleeps: list[float] = []

    async def record(seconds: float) -> None:
        sleeps.append(seconds)

    service = GeminiService(
        make_settings(gemini_max_retries=2),
        generate=FakeGenerate(api_error(503)),
        rate_limiter=RateLimiter(100, 100),
        sleep=record,
    )
    with pytest.raises(AIUnavailableError):
        await service.ask_tutor(**ASK)
    assert sleeps == [0.5, 1.0]


async def test_timeout_maps_to_ai_timeout() -> None:
    fake = FakeGenerate(5.0)  # hangs for 5 s
    with pytest.raises(AITimeoutError) as info:
        await make_gemini(fake, gemini_timeout_seconds=0.05).ask_tutor(**ASK)
    assert info.value.status_code == 504


async def test_local_rate_limit_blocks_before_calling_gemini() -> None:
    fake = FakeGenerate()
    service = make_gemini(fake, rate_limiter=RateLimiter(per_minute=1, per_day=100))
    await service.ask_tutor(**ASK)
    with pytest.raises(AIQuotaExceededError):
        await service.ask_tutor(**ASK)
    assert len(fake.calls) == 1


# ------------------------------------------------------------------ client configuration


@pytest.mark.parametrize("key", [None, "", "   "])
async def test_missing_api_key_is_not_configured(key: str | None) -> None:
    secret = None if key is None else SecretStr(key)  # model_copy does not validate
    service = GeminiService(make_settings(gemini_api_key=secret))
    with pytest.raises(AINotConfiguredError):
        await service.ask_tutor(**ASK)


def test_real_client_is_built_lazily_from_settings() -> None:
    """Constructing the SDK client makes no network call."""
    service = GeminiService(make_settings(gemini_api_key=SecretStr("test-key-not-real")))
    generate = service._get_generate()
    assert callable(generate)
    assert service._get_generate() is generate  # cached


def test_get_gemini_service_is_singleton() -> None:
    gemini_module.get_gemini_service.cache_clear()
    try:
        assert gemini_module.get_gemini_service() is gemini_module.get_gemini_service()
    finally:
        gemini_module.get_gemini_service.cache_clear()


def test_describe_answer_has_no_content() -> None:
    result = parse_answer(answer_json())
    summary = gemini_module.describe_answer(GeminiResult(result.answer, True, "gemini-3.5-flash"))
    assert summary == '{"model": "gemini-3.5-flash", "structured": true, "steps": 3, "checks": 2}'
