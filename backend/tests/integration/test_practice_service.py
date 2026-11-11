"""PracticeService against PostgreSQL: grading, points, streaks, progress, random questions."""

import time
from collections.abc import Callable

import pytest
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.errors import NotFoundError
from app.models import (
    Difficulty,
    PracticeAttempt,
    PracticeQuestion,
    QuestionType,
    Topic,
    Unit,
    User,
)
from app.repositories import ProgressRepository
from app.schemas.practice import PracticeSubmitRequest, PracticeSubmitResponse
from app.services.practice import practice_service as ps
from app.services.practice.practice_service import PracticeService, QuestionNotGradableError
from tests.fakes import make_settings

pytestmark = pytest.mark.integration


@pytest.fixture
def service(db_session: Session) -> PracticeService:
    return PracticeService(db_session, make_settings())


@pytest.fixture
def student(make_user: Callable[..., User]) -> User:
    return make_user()


@pytest.fixture
def unit(make_unit: Callable[..., Unit]) -> Unit:
    return make_unit(1, title="Complex Numbers")


@pytest.fixture
def topic(unit: Unit, make_topic: Callable[..., Topic]) -> Topic:
    return make_topic(unit, "Geometric Progression")


def submit(
    service: PracticeService,
    user: User,
    question: PracticeQuestion,
    answer: str,
    seconds: int = 30,
) -> PracticeSubmitResponse:
    return service.submit(
        user.id,
        PracticeSubmitRequest(
            question_id=question.id, student_answer=answer, time_taken_seconds=seconds
        ),
    )


# ------------------------------------------------------------------ submit


def test_first_correct_answer(
    service: PracticeService,
    student: User,
    topic: Topic,
    make_question: Callable[..., PracticeQuestion],
    db_session: Session,
) -> None:
    question = make_question(topic, difficulty=Difficulty.HARD, answer_explanation="S = a/(1-r)")
    result = submit(service, student, question, "1.5", seconds=30)

    assert result.is_correct is True
    assert (result.correct_answer, result.explanation) == ("3/2", "S = a/(1-r)")
    assert (result.points_earned, result.new_total_points) == (35, 35)  # hard 30 + bonus 5
    assert (result.streak, result.already_solved) == (1, False)
    assert result.encouragement == "Bilkul sahi! Bohat acha! ✅"

    progress = ProgressRepository(db_session).get_progress(student.id, topic.id)
    assert progress is not None
    assert (progress.attempts, progress.correct_count, progress.points) == (1, 1, 35)
    attempt = db_session.scalars(select(PracticeAttempt)).one()
    assert (attempt.is_correct, attempt.points_earned, attempt.time_taken_seconds) == (
        True,
        35,
        30,
    )


def test_wrong_answer_earns_nothing(
    service: PracticeService,
    student: User,
    topic: Topic,
    make_question: Callable[..., PracticeQuestion],
) -> None:
    result = submit(service, student, make_question(topic), "2/3", seconds=5)
    assert (result.is_correct, result.points_earned, result.new_total_points) == (False, 0, 0)
    assert result.streak == 0
    assert result.correct_answer == "3/2"  # revealed AFTER submitting
    assert result.encouragement == "Koi baat nahi, dobara koshish karo 💪"


def test_points_only_the_first_time_a_question_is_solved(
    service: PracticeService,
    student: User,
    topic: Topic,
    make_question: Callable[..., PracticeQuestion],
) -> None:
    question = make_question(topic, difficulty=Difficulty.MEDIUM)
    wrong = submit(service, student, question, "1", seconds=90)
    assert wrong.already_solved is False
    first = submit(service, student, question, "3/2", seconds=90)
    assert (first.points_earned, first.new_total_points, first.already_solved) == (20, 20, False)
    again = submit(service, student, question, "3/2", seconds=5)
    assert (again.points_earned, again.new_total_points, again.already_solved) == (0, 20, True)
    assert again.is_correct is True
    assert again.streak == 2  # repeats still count for the streak


def test_streak_celebration_and_broken_streak(
    service: PracticeService,
    student: User,
    topic: Topic,
    make_question: Callable[..., PracticeQuestion],
) -> None:
    questions = [make_question(topic, f"Q{i}") for i in range(4)]
    results = [submit(service, student, q, "3/2") for q in questions[:3]]
    assert [r.streak for r in results] == [1, 2, 3]
    assert results[2].encouragement == "Shabash! 3 sawaal lagataar sahi! 🔥"

    broken = submit(service, student, questions[3], "0")
    assert broken.streak == 0
    assert broken.encouragement == "Himmat mat haro! Agle mein zaroor sahi hoga 🌟"


def test_mcq_submission_by_letter(
    service: PracticeService,
    student: User,
    topic: Topic,
    make_question: Callable[..., PracticeQuestion],
) -> None:
    question = make_question(
        topic,
        question_type=QuestionType.MCQ,
        options=["11", "5", "-5", "8"],
        correct_answer="5",
    )
    assert submit(service, student, question, "b").is_correct is True
    assert submit(service, student, question, "A").is_correct is False


@pytest.mark.parametrize(
    "overrides",
    [{"question_type": QuestionType.PROOF}, {"correct_answer": "  "}],
    ids=["proof", "no-answer-key"],
)
def test_ungradable_questions_are_rejected(
    service: PracticeService,
    student: User,
    topic: Topic,
    make_question: Callable[..., PracticeQuestion],
    db_session: Session,
    overrides: dict[str, object],
) -> None:
    question = make_question(topic, **overrides)
    with pytest.raises(QuestionNotGradableError):
        submit(service, student, question, "anything")
    assert db_session.scalar(select(func.count()).select_from(PracticeAttempt)) == 0


def test_unknown_question(service: PracticeService, student: User) -> None:
    with pytest.raises(NotFoundError, match="Question 999999 not found"):
        service.submit(
            student.id,
            PracticeSubmitRequest(question_id=999_999, student_answer="1", time_taken_seconds=1),
        )


def test_slow_grading_falls_back_to_similarity(
    db_session: Session,
    student: User,
    topic: Topic,
    make_question: Callable[..., PracticeQuestion],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    def slow(*_: object) -> object:
        time.sleep(1)
        raise AssertionError("should have timed out")  # pragma: no cover

    monkeypatch.setattr(ps, "evaluate_answer", slow)
    service = PracticeService(db_session, make_settings(sympy_timeout_seconds=0.05))
    question = make_question(topic, correct_answer="3/2")
    assert submit(service, student, question, "3/2").is_correct is True  # identical text


# ------------------------------------------------------------------ random questions


@pytest.fixture
def mixed(
    make_unit: Callable[..., Unit],
    make_topic: Callable[..., Topic],
    make_question: Callable[..., PracticeQuestion],
) -> dict[str, Unit]:
    unit1, unit2 = make_unit(1, title="Complex Numbers"), make_unit(2, title="Matrices")
    t1, t2 = make_topic(unit1, "T1"), make_topic(unit2, "T2")
    for i in range(3):
        make_question(t1, f"U1 Q{i}")
    make_question(t1, "U1 proof", question_type=QuestionType.PROOF)
    make_question(t1, "U1 no key", correct_answer="")
    make_question(
        t2,
        "U2 mcq",
        question_type=QuestionType.MCQ,
        options=["a", "b", "c", "d"],
        correct_answer="c",
    )
    return {"u1": unit1, "u2": unit2}


def test_random_questions_skip_ungradable_and_hide_answers(
    service: PracticeService, mixed: dict[str, Unit]
) -> None:
    questions = service.random_questions(count=20)
    assert sorted(q.question_text for q in questions) == ["U1 Q0", "U1 Q1", "U1 Q2", "U2 mcq"]
    for q in questions:
        dumped = q.model_dump()
        assert "correct_answer" not in dumped
        assert "answer_explanation" not in dumped
    mcq = next(q for q in questions if q.question_type is QuestionType.MCQ)
    assert (mcq.options, mcq.unit_title, mcq.unit_number, mcq.topic_title) == (
        ["a", "b", "c", "d"],
        "Matrices",
        2,
        "T2",
    )


def test_random_questions_count_and_unit_filter(
    service: PracticeService, mixed: dict[str, Unit]
) -> None:
    assert len(service.random_questions(count=2)) == 2
    only_u2 = service.random_questions(count=5, unit_id=mixed["u2"].id)
    assert [q.question_text for q in only_u2] == ["U2 mcq"]
    with pytest.raises(NotFoundError, match="Unit 999999 not found"):
        service.random_questions(count=5, unit_id=999_999)


def test_random_questions_are_shuffled(service: PracticeService, mixed: dict[str, Unit]) -> None:
    orders = {tuple(q.id for q in service.random_questions(count=4)) for _ in range(30)}
    assert len(orders) > 1
