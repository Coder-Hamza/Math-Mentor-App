"""Practice and progress endpoints (seeded syllabus, rolled-back test DB)."""

from typing import Any

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.database.seed import SyllabusData
from app.models import PracticeQuestion, QuestionType, Topic, Unit
from tests.api.conftest import assert_error

pytestmark = pytest.mark.integration

API = "/api/v1"
ANSWER_FIELDS = {"correct_answer", "answer_explanation", "explanation"}


def _question(session: Session, topic_title: str) -> PracticeQuestion:
    stmt = select(PracticeQuestion).join(Topic).where(Topic.title == topic_title)
    return session.scalars(stmt).one()


def _submit(
    client: TestClient, headers: dict[str, str], question_id: int, answer: str, seconds: int = 30
) -> Any:
    return client.post(
        f"{API}/practice/submit",
        json={"question_id": question_id, "student_answer": answer, "time_taken_seconds": seconds},
        headers=headers,
    )


# ------------------------------------------------------------------ auth


@pytest.mark.parametrize(
    ("method", "path"),
    [
        ("get", "/practice/random"),
        ("post", "/practice/submit"),
        ("get", "/progress/"),
        ("get", "/progress/weak-topics"),
    ],
)
def test_requires_authentication(client: TestClient, method: str, path: str) -> None:
    response = client.request(method, f"{API}{path}", json={})
    assert response.status_code == 401
    assert_error(response.json(), "not_authenticated")


# ------------------------------------------------------------------ GET /practice/random


def test_random_returns_five_questions_without_answers(
    client: TestClient, auth_headers: dict[str, str], seeded: SyllabusData
) -> None:
    response = client.get(f"{API}/practice/random", headers=auth_headers)
    assert response.status_code == 200
    questions = response.json()
    assert len(questions) == 5
    for q in questions:
        assert ANSWER_FIELDS.isdisjoint(q)  # never show the answer before submitting
        assert q["question_type"] != "proof"
        assert {"id", "unit_title", "unit_number", "topic_title", "difficulty", "options"} <= set(q)
        assert (q["options"] is not None) == (q["question_type"] == "mcq")


def test_random_by_unit_and_count(
    client: TestClient, auth_headers: dict[str, str], seeded: SyllabusData, db_session: Session
) -> None:
    unit = db_session.scalars(select(Unit).where(Unit.unit_number == 10)).one()
    response = client.get(
        f"{API}/practice/random", params={"unit_id": unit.id, "count": 20}, headers=auth_headers
    )
    assert response.status_code == 200
    questions = response.json()
    # Unit 10 has 3 questions, two of them proofs.
    assert [(q["unit_number"], q["question_type"]) for q in questions] == [(10, "mcq")]


def test_random_returns_up_to_count_questions(
    client: TestClient, auth_headers: dict[str, str], seeded: SyllabusData
) -> None:
    response = client.get(f"{API}/practice/random", params={"count": 20}, headers=auth_headers)
    assert len(response.json()) == 20


def test_random_unknown_unit_is_404(
    client: TestClient, auth_headers: dict[str, str], seeded: SyllabusData
) -> None:
    response = client.get(
        f"{API}/practice/random", params={"unit_id": 999_999}, headers=auth_headers
    )
    assert response.status_code == 404
    assert_error(response.json(), "not_found")


@pytest.mark.parametrize(
    "params",
    [{"count": 0}, {"count": 21}, {"count": "five"}, {"unit_id": 0}, {"unit_id": 2**31}],
)
def test_random_invalid_params_are_422(
    client: TestClient, auth_headers: dict[str, str], params: dict[str, Any]
) -> None:
    response = client.get(f"{API}/practice/random", params=params, headers=auth_headers)
    assert response.status_code == 422
    assert_error(response.json(), "validation_error")


def test_topic_questions_endpoint_does_not_leak_answers(
    client: TestClient, auth_headers: dict[str, str], seeded: SyllabusData, db_session: Session
) -> None:
    question = _question(db_session, "Sigma Notation")
    response = client.get(f"{API}/topics/{question.topic_id}/questions", headers=auth_headers)
    (body,) = response.json()
    assert ANSWER_FIELDS.isdisjoint(body)
    assert body["options"] == ["120", "110", "121", "100"]


# ------------------------------------------------------------------ POST /practice/submit


def test_submit_correct_short_answer(
    client: TestClient, auth_headers: dict[str, str], seeded: SyllabusData, db_session: Session
) -> None:
    question = _question(db_session, "Geometric Progression")  # medium, answer 3/2
    response = _submit(client, auth_headers, question.id, "1.5", seconds=42)
    assert response.status_code == 200
    assert response.json() == {
        "is_correct": True,
        "correct_answer": "3/2",
        "explanation": question.answer_explanation,
        "points_earned": 25,
        "new_total_points": 25,
        "streak": 1,
        "encouragement": "Bilkul sahi! Bohat acha! ✅",
        "already_solved": False,
    }


def test_submit_wrong_answer(
    client: TestClient, auth_headers: dict[str, str], seeded: SyllabusData, db_session: Session
) -> None:
    question = _question(db_session, "Combinations")
    body = _submit(client, auth_headers, question.id, "35").json()
    assert (body["is_correct"], body["points_earned"], body["streak"]) == (False, 0, 0)
    assert body["correct_answer"] == "350"
    assert body["encouragement"] == "Koi baat nahi, dobara koshish karo 💪"


def test_submit_mcq_by_letter_and_streak(
    client: TestClient, auth_headers: dict[str, str], seeded: SyllabusData, db_session: Session
) -> None:
    sigma = _question(db_session, "Sigma Notation")  # easy MCQ, option A
    pakistan = _question(db_session, "Permutations")  # easy MCQ, option A
    binomial = _question(db_session, "General Term and Middle Term")  # medium MCQ, option B
    assert sigma.question_type is QuestionType.MCQ

    results = [
        _submit(client, auth_headers, sigma.id, "A", seconds=10).json(),
        _submit(client, auth_headers, pakistan.id, "20160", seconds=100).json(),
        _submit(client, auth_headers, binomial.id, "b", seconds=10).json(),
    ]
    assert [r["points_earned"] for r in results] == [15, 10, 25]
    assert [r["new_total_points"] for r in results] == [15, 25, 50]
    assert results[2]["encouragement"] == "Shabash! 3 sawaal lagataar sahi! 🔥"

    broken = _submit(client, auth_headers, sigma.id, "D").json()
    assert broken["is_correct"] is False
    assert broken["encouragement"] == "Himmat mat haro! Agle mein zaroor sahi hoga 🌟"


def test_resubmitting_a_solved_question_earns_no_points(
    client: TestClient, auth_headers: dict[str, str], seeded: SyllabusData, db_session: Session
) -> None:
    question = _question(db_session, "Combinations")
    _submit(client, auth_headers, question.id, "350")
    again = _submit(client, auth_headers, question.id, "350").json()
    assert (again["points_earned"], again["new_total_points"], again["already_solved"]) == (
        0,
        25,
        True,
    )


def test_submit_proof_is_not_gradable(
    client: TestClient, auth_headers: dict[str, str], seeded: SyllabusData, db_session: Session
) -> None:
    question = _question(db_session, "Principle of Mathematical Induction")
    response = _submit(client, auth_headers, question.id, "n^2")
    assert response.status_code == 422
    assert_error(response.json(), "question_not_gradable")


def test_submit_unknown_question_is_404(
    client: TestClient, auth_headers: dict[str, str], seeded: SyllabusData
) -> None:
    response = _submit(client, auth_headers, 999_999, "1")
    assert response.status_code == 404
    assert_error(response.json(), "not_found")


@pytest.mark.parametrize(
    "payload",
    [
        {"question_id": 1, "student_answer": "   ", "time_taken_seconds": 5},
        {"question_id": 1, "student_answer": "x" * 501, "time_taken_seconds": 5},
        {"question_id": 1, "student_answer": "1", "time_taken_seconds": -1},
        {"question_id": 1, "student_answer": "1", "time_taken_seconds": 86_401},
        {"question_id": 0, "student_answer": "1", "time_taken_seconds": 5},
        {"question_id": 1, "student_answer": "1"},
        {"question_id": 1, "student_answer": "1", "time_taken_seconds": 5, "points": 999},
    ],
)
def test_submit_invalid_payload_is_422(
    client: TestClient, auth_headers: dict[str, str], payload: dict[str, Any]
) -> None:
    response = client.post(f"{API}/practice/submit", json=payload, headers=auth_headers)
    assert response.status_code == 422
    assert_error(response.json(), "validation_error")


def test_hostile_answer_is_handled_safely(
    client: TestClient, auth_headers: dict[str, str], seeded: SyllabusData, db_session: Session
) -> None:
    question = _question(db_session, "Combinations")
    for answer in ["__import__('os').system('echo hi')", "9**9**9**9", "factorial(10**9)"]:
        response = _submit(client, auth_headers, question.id, answer)
        assert response.status_code == 200
        assert response.json()["is_correct"] is False


# ------------------------------------------------------------------ progress


def test_progress_for_new_student(
    client: TestClient, auth_headers: dict[str, str], seeded: SyllabusData
) -> None:
    response = client.get(f"{API}/progress/", headers=auth_headers)
    assert response.status_code == 200
    body = response.json()
    assert {k: v for k, v in body.items() if k != "units_progress"} == {
        "total_points": 0,
        "total_attempted": 0,
        "total_correct": 0,
        "accuracy_percent": 0.0,
        "current_streak": 0,
    }
    units = body["units_progress"]
    assert [u["unit_number"] for u in units] == list(range(1, 13))
    assert set(units[0]) == {
        "unit_id",
        "unit_number",
        "unit_title",
        "topics_attempted",
        "topics_total",
        "avg_score",
        "progress_percent",
    }
    assert units[9]["topics_total"] == 1  # unit 10: the two proof topics are not practisable
    assert all(u["topics_total"] >= 1 for u in units)


def test_progress_and_weak_topics_after_practice(
    client: TestClient, auth_headers: dict[str, str], seeded: SyllabusData, db_session: Session
) -> None:
    gp = _question(db_session, "Geometric Progression")
    combos = _question(db_session, "Combinations")
    _submit(client, auth_headers, gp.id, "3/2", seconds=100)  # 20 points
    _submit(client, auth_headers, combos.id, "1")  # wrong
    _submit(client, auth_headers, combos.id, "2")  # wrong

    body = client.get(f"{API}/progress/", headers=auth_headers).json()
    assert (body["total_points"], body["total_attempted"], body["total_correct"]) == (20, 3, 1)
    assert (body["accuracy_percent"], body["current_streak"]) == (33.3, 0)
    unit4 = body["units_progress"][3]
    assert (unit4["topics_attempted"], unit4["avg_score"]) == (1, 100.0)

    weak = client.get(f"{API}/progress/weak-topics", headers=auth_headers).json()
    assert [(w["topic_title"], w["accuracy_percent"], w["attempts"]) for w in weak] == [
        ("Combinations", 0.0, 2)
    ]
    assert weak[0]["unit_number"] == 6


def test_weak_topics_empty_for_new_student(
    client: TestClient, auth_headers: dict[str, str], seeded: SyllabusData
) -> None:
    response = client.get(f"{API}/progress/weak-topics", headers=auth_headers)
    assert (response.status_code, response.json()) == (200, [])
