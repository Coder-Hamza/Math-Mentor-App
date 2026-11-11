"""POST /api/v1/tutor/ask — success, auth, validation, AI failures, and privacy."""

from collections.abc import Callable
from typing import Any

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from app.api.routes.tutor import get_tutor_service
from app.database.seed import SyllabusData
from app.repositories import TopicRepository, UnitRepository
from app.schemas.ai_schemas import TutorRequest, TutorResponse, VerificationStatus
from app.services.ai.gemini_service import get_gemini_service
from tests.api.conftest import assert_error
from tests.fakes import FakeGenerate, answer_json, api_error, make_gemini

pytestmark = pytest.mark.integration

ASK = "/api/v1/tutor/ask"


@pytest.fixture
def topic_id(db_session: Session, seeded: SyllabusData) -> int:
    unit = UnitRepository(db_session).get_by_number(10)
    assert unit is not None
    topic = TopicRepository(db_session).get_by_title(unit.id, "Double and Half Angle Identities")
    assert topic is not None
    return topic.id


@pytest.fixture
def use_gemini(app: FastAPI) -> Callable[..., FakeGenerate]:
    """Install a fake Gemini transport (the full real pipeline runs, minus the network)."""

    def install(*outcomes: object, **settings: Any) -> FakeGenerate:
        fake = FakeGenerate(*outcomes)
        service = make_gemini(fake, **({"gemini_max_retries": 0} | settings))
        app.dependency_overrides[get_gemini_service] = lambda: service
        return fake

    return install


def _ask(client: TestClient, headers: dict[str, str], topic_id: int, **body: Any) -> Any:
    payload = {"question": "Prove sin 2x = 2 sin x cos x", "topic_id": topic_id} | body
    return client.post(ASK, json=payload, headers=headers)


# ------------------------------------------------------------------ success


def test_ask_returns_verified_answer(
    client: TestClient,
    auth_headers: dict[str, str],
    topic_id: int,
    use_gemini: Callable[..., FakeGenerate],
) -> None:
    use_gemini(answer_json())
    response = _ask(client, auth_headers, topic_id)

    assert response.status_code == 200
    body = response.json()
    assert set(body) == set(TutorResponse.model_fields)
    assert body["sympy_verified"] is True
    assert body["verification_status"] == "verified"
    assert body["verification_confidence"] == 1.0
    assert body["topic"] == "Double and Half Angle Identities"
    assert body["unit"] == "Trigonometric Identities of Sum and Difference of Angles"
    assert len(body["steps"]) == 3
    assert body["warning"] is None


def test_wrong_math_returns_200_with_warning(
    client: TestClient,
    auth_headers: dict[str, str],
    topic_id: int,
    use_gemini: Callable[..., FakeGenerate],
) -> None:
    use_gemini(answer_json(checks=[{"lhs": "cos(2*x)", "rhs": "2*cos(x)"}]))
    body = _ask(client, auth_headers, topic_id).json()
    assert body["verification_status"] == "failed"
    assert body["sympy_verified"] is False
    assert "possible mistake" in body["warning"]


def test_non_json_gemini_reply_returns_200(
    client: TestClient,
    auth_headers: dict[str, str],
    topic_id: int,
    use_gemini: Callable[..., FakeGenerate],
) -> None:
    use_gemini("Here is my answer in plain words.")
    response = _ask(client, auth_headers, topic_id)
    assert response.status_code == 200
    assert response.json()["explanation"] == "Here is my answer in plain words."
    assert response.json()["verification_status"] == "unverifiable"


def test_english_language_option(
    client: TestClient,
    auth_headers: dict[str, str],
    topic_id: int,
    use_gemini: Callable[..., FakeGenerate],
) -> None:
    fake = use_gemini()
    assert _ask(client, auth_headers, topic_id, language="english").status_code == 200
    assert "simple, clear English" in fake.calls[0]["contents"]


def test_tutor_service_can_be_mocked_entirely(
    app: FastAPI, client: TestClient, auth_headers: dict[str, str]
) -> None:
    class StubTutor:
        async def ask(self, request: TutorRequest) -> TutorResponse:
            return TutorResponse(
                question=request.question,
                explanation="stub",
                steps=["1"],
                formulas_used=[],
                sympy_verified=False,
                verification_confidence=0.0,
                verification_status=VerificationStatus.UNVERIFIABLE,
                topic="T",
                unit="U",
                warning="w",
            )

    app.dependency_overrides[get_tutor_service] = StubTutor
    response = client.post(ASK, json={"question": "Q", "topic_id": 1}, headers=auth_headers)
    assert response.status_code == 200
    assert response.json()["explanation"] == "stub"


# ------------------------------------------------------------------ auth + validation


def test_requires_authentication(client: TestClient, topic_id: int) -> None:
    response = client.post(ASK, json={"question": "Q", "topic_id": topic_id})
    assert response.status_code == 401
    assert_error(response.json(), "not_authenticated")


@pytest.mark.parametrize(
    "payload",
    [
        {"question": "x" * 501, "topic_id": 1},
        {"question": "   ", "topic_id": 1},
        {"question": "Q"},
        {"topic_id": 1},
        {"question": "Q", "topic_id": 0},
        {"question": "Q", "topic_id": 1, "language": "french"},
        {"question": "Q", "topic_id": 1, "student_name": "Ali"},
    ],
)
def test_invalid_request_is_422(
    client: TestClient, auth_headers: dict[str, str], payload: dict[str, Any]
) -> None:
    response = client.post(ASK, json=payload, headers=auth_headers)
    assert response.status_code == 422
    assert_error(response.json(), "validation_error")


def test_question_of_exactly_500_chars_is_accepted(
    client: TestClient,
    auth_headers: dict[str, str],
    topic_id: int,
    use_gemini: Callable[..., FakeGenerate],
) -> None:
    use_gemini()
    assert _ask(client, auth_headers, topic_id, question="x" * 500).status_code == 200


def test_unknown_topic_is_404(
    client: TestClient, auth_headers: dict[str, str], use_gemini: Callable[..., FakeGenerate]
) -> None:
    fake = use_gemini()
    response = client.post(ASK, json={"question": "Q", "topic_id": 999999}, headers=auth_headers)
    assert response.status_code == 404
    assert_error(response.json(), "not_found")
    assert fake.calls == []


# ------------------------------------------------------------------ Gemini failures


@pytest.mark.parametrize(
    ("outcome", "status", "code"),
    [
        (api_error(503), 503, "ai_unavailable"),
        (api_error(500), 503, "ai_unavailable"),
        (api_error(401), 503, "ai_not_configured"),
        (api_error(404), 503, "ai_not_configured"),
        (api_error(429), 429, "ai_quota_exceeded"),
        ("", 502, "ai_bad_response"),
    ],
)
def test_gemini_failures_map_to_friendly_errors(
    client: TestClient,
    auth_headers: dict[str, str],
    topic_id: int,
    use_gemini: Callable[..., FakeGenerate],
    outcome: object,
    status: int,
    code: str,
) -> None:
    use_gemini(outcome)
    response = _ask(client, auth_headers, topic_id)
    assert response.status_code == status
    assert_error(response.json(), code)
    assert "simulated" not in response.text  # SDK details never leak


def test_quota_error_sets_retry_after(
    client: TestClient,
    auth_headers: dict[str, str],
    topic_id: int,
    use_gemini: Callable[..., FakeGenerate],
) -> None:
    use_gemini(api_error(429))
    assert _ask(client, auth_headers, topic_id).headers["retry-after"] == "60"


def test_gemini_timeout_is_504(
    client: TestClient,
    auth_headers: dict[str, str],
    topic_id: int,
    use_gemini: Callable[..., FakeGenerate],
) -> None:
    use_gemini(5.0, gemini_timeout_seconds=0.05)
    response = _ask(client, auth_headers, topic_id)
    assert response.status_code == 504
    assert_error(response.json(), "ai_timeout")


def test_gemini_not_configured_is_503(
    app: FastAPI, client: TestClient, auth_headers: dict[str, str], topic_id: int
) -> None:
    from app.services.ai.gemini_service import GeminiService
    from tests.fakes import make_settings

    app.dependency_overrides[get_gemini_service] = lambda: GeminiService(
        make_settings(gemini_api_key=None)
    )
    response = _ask(client, auth_headers, topic_id)
    assert response.status_code == 503
    assert_error(response.json(), "ai_not_configured")


# ------------------------------------------------------------------ privacy


def test_no_student_personal_data_reaches_gemini(
    client: TestClient, topic_id: int, use_gemini: Callable[..., FakeGenerate]
) -> None:
    name, email, password = "Zainab Qureshi Unique", "zainab.private@example.com", "pw-123456789"
    client.post("/api/v1/auth/register", json={"email": email, "name": name, "password": password})
    login = client.post("/api/v1/auth/login", json={"email": email, "password": password}).json()
    headers = {"Authorization": f"Bearer {login['access_token']}"}
    me = client.get("/api/v1/auth/me", headers=headers).json()

    fake = use_gemini()
    question = f"My email is {email} and phone 0300-1234567. Solve x^2 - 4 = 0"
    response = _ask(client, headers, topic_id, question=question)

    assert response.status_code == 200
    sent = fake.sent_text()
    for secret in (name, "Zainab", "Qureshi", email, "0300-1234567", password):
        assert secret not in sent, f"{secret!r} was sent to Gemini"
    assert login["access_token"] not in sent
    assert f"user {me['id']}" not in sent.lower()
    assert "Solve x^2 - 4 = 0" in sent  # the maths itself is still sent
