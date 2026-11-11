"""POST /api/v1/solver/solve — success, book-answer checks, auth, validation, AI failures."""

from collections.abc import Callable
from typing import Any

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.schemas.solver_schemas import SolverResponse
from app.services.ai.gemini_service import get_gemini_service
from tests.api.conftest import assert_error
from tests.fakes import FakeGenerate, api_error, make_gemini, solution_json

pytestmark = pytest.mark.integration

SOLVE = "/api/v1/solver/solve"


@pytest.fixture
def use_gemini(app: FastAPI) -> Callable[..., FakeGenerate]:
    """Install a fake Gemini transport (the full real pipeline runs, minus the network)."""

    def install(*outcomes: object, **settings: Any) -> FakeGenerate:
        fake = FakeGenerate(*outcomes)
        service = make_gemini(fake, **({"gemini_max_retries": 0} | settings))
        app.dependency_overrides[get_gemini_service] = lambda: service
        return fake

    return install


def _solve(client: TestClient, headers: dict[str, str], **body: Any) -> Any:
    payload = {"chapter_name": "Quadratic Equations", "question": "Solve x^2 - 5x + 6 = 0"}
    return client.post(SOLVE, json=payload | body, headers=headers)


def test_solve_returns_full_solution(
    client: TestClient, auth_headers: dict[str, str], use_gemini: Callable[..., FakeGenerate]
) -> None:
    use_gemini(solution_json())
    response = _solve(client, auth_headers)

    assert response.status_code == 200
    body = response.json()
    assert set(body) == set(SolverResponse.model_fields)
    assert body["chapter"] == "Quadratic Equations"
    assert body["our_answer"] == "x = 2, x = 3"
    assert body["sympy_verified"] is True
    assert body["answer_verified"] is False
    assert body["book_answer"] is None
    assert len(body["steps"]) == 3
    assert body["steps"][1] == {
        "step_number": 2,
        "title": "Factorise karein",
        "explanation": "Common factors bahar nikalein.",
        "formula_used": "Factorisation: ab = 0 => a = 0 or b = 0",
        "calculation": "(x - 2)(x - 3) = 0",
    }
    assert body["solution"].startswith("Sawal:")
    assert "Jawab: x = 2, x = 3" in body["solution"]
    assert body["pro_tip"]
    assert body["difficulty_level"] == "easy"


def test_matching_book_answer_sets_answer_verified(
    client: TestClient, auth_headers: dict[str, str], use_gemini: Callable[..., FakeGenerate]
) -> None:
    use_gemini(solution_json())
    body = _solve(client, auth_headers, book_answer="x = 3, x = 2").json()
    assert body["answer_verified"] is True
    assert body["book_answer"] == "x = 3, x = 2"
    assert body["warning"] is None


def test_different_book_answer_is_reported(
    client: TestClient, auth_headers: dict[str, str], use_gemini: Callable[..., FakeGenerate]
) -> None:
    use_gemini(solution_json())
    body = _solve(client, auth_headers, book_answer="x = -2, x = -3").json()
    assert body["answer_verified"] is False
    assert "book ke jawab se match nahi" in body["warning"]


def test_empty_book_answer_counts_as_none(
    client: TestClient, auth_headers: dict[str, str], use_gemini: Callable[..., FakeGenerate]
) -> None:
    fake = use_gemini(solution_json())
    body = _solve(client, auth_headers, book_answer="").json()
    assert body["book_answer"] is None
    assert "Book ka jawab" not in fake.sent_text()


def test_requires_login(client: TestClient, use_gemini: Callable[..., FakeGenerate]) -> None:
    fake = use_gemini(solution_json())
    response = _solve(client, {})
    assert response.status_code == 401
    assert_error(response.json(), "not_authenticated")
    assert fake.calls == []


@pytest.mark.parametrize(
    "body",
    [
        {"chapter_name": ""},
        {"question": ""},
        {"question": "q" * 1001},
        {"chapter_name": "c" * 201},
        {"book_answer": "b" * 501},
        {"language": "klingon"},
        {"user_id": 1},
    ],
)
def test_validation_errors(
    client: TestClient,
    auth_headers: dict[str, str],
    use_gemini: Callable[..., FakeGenerate],
    body: dict[str, Any],
) -> None:
    fake = use_gemini(solution_json())
    response = _solve(client, auth_headers, **body)
    assert response.status_code == 422
    assert_error(response.json(), "validation_error")
    assert "q" * 50 not in response.text  # input is never echoed
    assert fake.calls == []


def test_missing_question_is_422(
    client: TestClient, auth_headers: dict[str, str], use_gemini: Callable[..., FakeGenerate]
) -> None:
    use_gemini(solution_json())
    response = client.post(SOLVE, json={"chapter_name": "Vectors"}, headers=auth_headers)
    assert response.status_code == 422


def test_timeout_is_504(
    client: TestClient, auth_headers: dict[str, str], use_gemini: Callable[..., FakeGenerate]
) -> None:
    # The Gemini call's own limit (solver budget = 1.1 - 0.1 s) cuts the hanging request.
    use_gemini(5.0, solver_timeout_seconds=1.1, sympy_timeout_seconds=0.1)
    response = _solve(client, auth_headers)
    assert response.status_code == 504
    assert_error(response.json(), "ai_timeout")


def test_quota_is_429_with_retry_after(
    client: TestClient, auth_headers: dict[str, str], use_gemini: Callable[..., FakeGenerate]
) -> None:
    use_gemini(api_error(429, retry_delay="20s"), gemini_fallback_model=None)
    response = _solve(client, auth_headers)
    assert response.status_code == 429
    assert response.headers["Retry-After"] == "20"
    assert_error(response.json(), "ai_quota_exceeded")


def test_gemini_down_is_503(
    client: TestClient, auth_headers: dict[str, str], use_gemini: Callable[..., FakeGenerate]
) -> None:
    use_gemini(api_error(500))
    response = _solve(client, auth_headers)
    assert response.status_code == 503
    assert_error(response.json(), "ai_unavailable")


def test_no_personal_data_reaches_gemini(
    client: TestClient, auth_headers: dict[str, str], use_gemini: Callable[..., FakeGenerate]
) -> None:
    fake = use_gemini(solution_json())
    _solve(client, auth_headers, question="My email is me@example.com. Solve x + 1 = 2")
    sent = fake.sent_text()
    assert "me@example.com" not in sent
    assert "student@example.com" not in sent  # the logged-in user is never sent
