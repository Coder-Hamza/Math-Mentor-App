"""ProgressRepository against PostgreSQL: every method, plus isolation between students."""

from collections.abc import Callable

import pytest
from sqlalchemy.orm import Session

from app.models import PracticeQuestion, QuestionType, Topic, Unit, User
from app.repositories import ProgressRepository

pytestmark = pytest.mark.integration


@pytest.fixture
def repo(db_session: Session) -> ProgressRepository:
    return ProgressRepository(db_session)


@pytest.fixture
def student(make_user: Callable[..., User]) -> User:
    return make_user("student@example.com")


@pytest.fixture
def other(make_user: Callable[..., User]) -> User:
    return make_user("other@example.com")


@pytest.fixture
def topic(make_unit: Callable[..., Unit], make_topic: Callable[..., Topic]) -> Topic:
    return make_topic(make_unit(1), "Algebra")


# ------------------------------------------------------------------ per topic


def test_get_or_create_progress_is_idempotent(
    repo: ProgressRepository, student: User, topic: Topic
) -> None:
    assert repo.get_progress(student.id, topic.id) is None
    first = repo.get_or_create_progress(student.id, topic.id)
    assert (first.attempts, first.correct_count, first.points, first.score) == (0, 0, 0, 0.0)
    assert repo.get_or_create_progress(student.id, topic.id) is first
    assert repo.get_progress(student.id, topic.id) is first


def test_update_after_attempt(repo: ProgressRepository, student: User, topic: Topic) -> None:
    progress = repo.update_after_attempt(student.id, topic.id, is_correct=True, points=15)
    assert (progress.attempts, progress.correct_count, progress.points) == (1, 1, 15)
    assert progress.score == 100.0
    assert progress.last_attempted is not None

    repo.update_after_attempt(student.id, topic.id, is_correct=False, points=0)
    progress = repo.update_after_attempt(student.id, topic.id, is_correct=False, points=0)
    assert (progress.attempts, progress.correct_count, progress.points) == (3, 1, 15)
    assert progress.score == pytest.approx(33.33)


def test_update_after_attempt_rejects_negative_points(
    repo: ProgressRepository, student: User, topic: Topic
) -> None:
    with pytest.raises(ValueError, match="negative"):
        repo.update_after_attempt(student.id, topic.id, is_correct=True, points=-1)


# ------------------------------------------------------------------ attempt log


def test_has_solved_only_counts_own_correct_attempts(
    repo: ProgressRepository,
    student: User,
    other: User,
    topic: Topic,
    make_question: Callable[..., PracticeQuestion],
) -> None:
    question = make_question(topic)
    repo.record_attempt(student.id, question.id, is_correct=False, points=0, time_taken_seconds=5)
    assert repo.has_solved(student.id, question.id) is False
    repo.record_attempt(other.id, question.id, is_correct=True, points=10, time_taken_seconds=5)
    assert repo.has_solved(student.id, question.id) is False
    attempt = repo.record_attempt(
        student.id, question.id, is_correct=True, points=10, time_taken_seconds=70
    )
    assert attempt.id is not None
    assert attempt.created_at is not None
    assert repo.has_solved(student.id, question.id) is True


def test_current_streak(
    repo: ProgressRepository,
    student: User,
    other: User,
    topic: Topic,
    make_question: Callable[..., PracticeQuestion],
) -> None:
    question = make_question(topic)

    def answer(user: User, correct: bool) -> None:
        repo.record_attempt(
            user.id, question.id, is_correct=correct, points=0, time_taken_seconds=1
        )

    assert repo.current_streak(student.id) == 0
    answer(student, True)
    answer(student, True)
    assert repo.current_streak(student.id) == 2
    answer(other, False)  # someone else's wrong answer does not break my streak
    answer(student, True)
    assert repo.current_streak(student.id) == 3
    answer(student, False)
    assert repo.current_streak(student.id) == 0
    answer(student, True)
    assert repo.current_streak(student.id) == 1
    assert repo.current_streak(other.id) == 0


def test_total_points(
    repo: ProgressRepository,
    student: User,
    other: User,
    make_unit: Callable[..., Unit],
    make_topic: Callable[..., Topic],
) -> None:
    unit = make_unit(1)
    first, second = make_topic(unit, "A"), make_topic(unit, "B")
    assert repo.total_points(student.id) == 0
    repo.update_after_attempt(student.id, first.id, is_correct=True, points=15)
    repo.update_after_attempt(student.id, second.id, is_correct=True, points=30)
    repo.update_after_attempt(other.id, first.id, is_correct=True, points=99)
    assert repo.total_points(student.id) == 45


# ------------------------------------------------------------------ summaries


@pytest.fixture
def syllabus(
    make_unit: Callable[..., Unit],
    make_topic: Callable[..., Topic],
    make_question: Callable[..., PracticeQuestion],
) -> dict[str, Topic]:
    """Unit 1: three practisable topics + a proof-only topic + a topic with no answer key.
    Unit 2: one practisable topic."""
    unit1, unit2 = make_unit(1, title="Complex Numbers"), make_unit(2, title="Matrices")
    topics = {
        "a": make_topic(unit1, "A"),
        "b": make_topic(unit1, "B"),
        "c": make_topic(unit1, "C"),
        "proof": make_topic(unit1, "Proofs"),
        "no_key": make_topic(unit1, "No key"),
        "m": make_topic(unit2, "M"),
    }
    for name in ("a", "b", "c", "m"):
        make_question(topics[name])
    make_question(topics["proof"], question_type=QuestionType.PROOF)
    make_question(topics["no_key"], correct_answer="")
    return topics


def test_overall_progress_for_a_new_student(
    repo: ProgressRepository, student: User, syllabus: dict[str, Topic]
) -> None:
    summary = repo.get_overall_progress(student.id)
    assert (summary.total_points, summary.total_attempted, summary.total_correct) == (0, 0, 0)
    assert (summary.accuracy_percent, summary.current_streak) == (0.0, 0)
    assert [
        (u.unit_number, u.topics_total, u.topics_attempted) for u in summary.units_progress
    ] == [
        (1, 3, 0),
        (2, 1, 0),
    ]
    assert all(u.avg_score == u.progress_percent == 0.0 for u in summary.units_progress)


def test_overall_and_unit_progress(
    repo: ProgressRepository,
    student: User,
    other: User,
    syllabus: dict[str, Topic],
    make_question: Callable[..., PracticeQuestion],
) -> None:
    question = make_question(syllabus["a"], "streak question")
    # Topic A: 1/1 (100%), topic B: 1/2 (50%), unit 2 untouched.
    repo.update_after_attempt(student.id, syllabus["a"].id, is_correct=True, points=15)
    repo.update_after_attempt(student.id, syllabus["b"].id, is_correct=False, points=0)
    repo.update_after_attempt(student.id, syllabus["b"].id, is_correct=True, points=20)
    repo.update_after_attempt(other.id, syllabus["m"].id, is_correct=True, points=50)
    repo.record_attempt(student.id, question.id, is_correct=True, points=0, time_taken_seconds=1)

    summary = repo.get_overall_progress(student.id)
    assert (summary.total_points, summary.total_attempted, summary.total_correct) == (35, 3, 2)
    assert summary.accuracy_percent == 66.7
    assert summary.current_streak == 1

    unit1, unit2 = summary.units_progress
    assert (unit1.unit_title, unit1.topics_attempted, unit1.topics_total) == (
        "Complex Numbers",
        2,
        3,
    )
    assert unit1.avg_score == 75.0  # (100 + 50) / 2 attempted topics
    assert unit1.progress_percent == 50.0  # (100 + 50) / 3 practisable topics
    assert (unit2.topics_attempted, unit2.progress_percent) == (0, 0.0)

    single = repo.get_unit_progress(student.id, unit1.unit_id)
    assert single == unit1
    assert repo.get_unit_progress(student.id, 999_999) is None


def test_progress_percent_never_exceeds_100(
    repo: ProgressRepository, student: User, syllabus: dict[str, Topic]
) -> None:
    # Progress on a topic that no longer has gradable questions still counts, capped at 100%.
    for name in ("a", "b", "c", "proof"):
        repo.update_after_attempt(student.id, syllabus[name].id, is_correct=True, points=10)
    unit1 = repo.get_overall_progress(student.id).units_progress[0]
    assert (unit1.topics_attempted, unit1.topics_total, unit1.progress_percent) == (4, 3, 100.0)


def test_weak_topics(
    repo: ProgressRepository, student: User, other: User, syllabus: dict[str, Topic]
) -> None:
    def attempts(topic: str, correct: int, wrong: int, user: User = student) -> None:
        for _ in range(correct):
            repo.update_after_attempt(user.id, syllabus[topic].id, is_correct=True, points=10)
        for _ in range(wrong):
            repo.update_after_attempt(user.id, syllabus[topic].id, is_correct=False, points=0)

    attempts("a", correct=1, wrong=1)  # 50% -> weak
    attempts("b", correct=3, wrong=2)  # 60% -> not weak (threshold is "< 60")
    attempts("c", correct=0, wrong=2)  # 0% -> weakest
    attempts("m", correct=0, wrong=5, user=other)  # other student's weakness
    repo.get_or_create_progress(student.id, syllabus["m"].id)  # 0 attempts -> not weak

    weak = repo.get_weak_topics(student.id)
    assert [(w.topic_title, w.accuracy_percent) for w in weak] == [("C", 0.0), ("A", 50.0)]
    first = weak[0]
    assert (first.unit_number, first.unit_title, first.attempts, first.correct) == (
        1,
        "Complex Numbers",
        2,
        0,
    )
    assert repo.get_weak_topics(other.id)[0].topic_title == "M"
