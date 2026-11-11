"""Model behaviour against real PostgreSQL: defaults, constraints, cascades."""

from collections.abc import Callable
from datetime import UTC, datetime

import pytest
from sqlalchemy import delete, func, select, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.models import (
    Difficulty,
    Formula,
    PracticeQuestion,
    QuestionType,
    StudentProgress,
    Topic,
    Unit,
    User,
)

pytestmark = pytest.mark.integration


def test_user_server_defaults(db_session: Session, make_user: Callable[..., User]) -> None:
    user = make_user()
    db_session.refresh(user)
    assert user.is_active is True
    assert user.created_at.tzinfo is not None
    assert abs((datetime.now(UTC) - user.created_at).total_seconds()) < 300


def test_user_email_unique(db_session: Session, make_user: Callable[..., User]) -> None:
    make_user(email="dup@example.com")
    with pytest.raises(IntegrityError):
        make_user(email="dup@example.com")


def test_unit_number_unique(db_session: Session, make_unit: Callable[..., Unit]) -> None:
    make_unit(1)
    with pytest.raises(IntegrityError):
        make_unit(1)


@pytest.mark.parametrize("column", ["unit_number", "page_number"])
def test_unit_numbers_must_be_positive(
    db_session: Session, make_unit: Callable[..., Unit], column: str
) -> None:
    kwargs = {"unit_number": 5, "page_number": 1} | {column: 0}
    with pytest.raises(IntegrityError, match="positive"):
        make_unit(**kwargs)


def test_topic_title_unique_within_unit(
    db_session: Session, make_unit: Callable[..., Unit], make_topic: Callable[..., Topic]
) -> None:
    unit_a, unit_b = make_unit(1), make_unit(2)
    make_topic(unit_a, "Vectors")
    make_topic(unit_b, "Vectors")  # same title in another unit is fine
    with pytest.raises(IntegrityError):
        make_topic(unit_a, "Vectors")


def test_enum_check_constraint_enforced_in_database(
    db_session: Session, make_unit: Callable[..., Unit]
) -> None:
    unit = make_unit(1)
    with pytest.raises(IntegrityError, match="difficulty_level"):
        db_session.execute(
            text("INSERT INTO topics (unit_id, title, difficulty_level) VALUES (:u, 'T', 'x')"),
            {"u": unit.id},
        )


def test_enum_round_trip(
    db_session: Session, make_unit: Callable[..., Unit], make_topic: Callable[..., Topic]
) -> None:
    topic = make_topic(make_unit(1), difficulty_level=Difficulty.HARD)
    question = PracticeQuestion(
        topic_id=topic.id, question_text="Prove it.", question_type=QuestionType.PROOF
    )
    db_session.add(question)
    db_session.flush()
    db_session.expire_all()
    stored = db_session.execute(
        text("SELECT difficulty, question_type FROM practice_questions WHERE id = :id"),
        {"id": question.id},
    ).one()
    assert tuple(stored) == ("medium", "proof")  # values, not member names
    assert db_session.get(Topic, topic.id).difficulty_level is Difficulty.HARD  # type: ignore[union-attr]


@pytest.mark.parametrize(
    ("score", "attempts", "constraint"),
    [(100.5, 0, "score_range"), (-1, 0, "score_range"), (50, -1, "attempts_non_negative")],
)
def test_progress_check_constraints(
    db_session: Session,
    make_unit: Callable[..., Unit],
    make_topic: Callable[..., Topic],
    make_user: Callable[..., User],
    score: float,
    attempts: int,
    constraint: str,
) -> None:
    topic, user = make_topic(make_unit(1)), make_user()
    db_session.add(
        StudentProgress(user_id=user.id, topic_id=topic.id, score=score, attempts=attempts)
    )
    with pytest.raises(IntegrityError, match=constraint):
        db_session.flush()


def test_progress_unique_per_user_and_topic(
    db_session: Session,
    make_unit: Callable[..., Unit],
    make_topic: Callable[..., Topic],
    make_user: Callable[..., User],
) -> None:
    topic, user = make_topic(make_unit(1)), make_user()
    db_session.add(StudentProgress(user_id=user.id, topic_id=topic.id))
    db_session.flush()
    db_session.add(StudentProgress(user_id=user.id, topic_id=topic.id))
    with pytest.raises(IntegrityError):
        db_session.flush()


def test_progress_defaults(
    db_session: Session,
    make_unit: Callable[..., Unit],
    make_topic: Callable[..., Topic],
    make_user: Callable[..., User],
) -> None:
    progress = StudentProgress(user_id=make_user().id, topic_id=make_topic(make_unit(1)).id)
    db_session.add(progress)
    db_session.flush()
    db_session.refresh(progress)
    assert (progress.score, progress.attempts, progress.last_attempted) == (0.0, 0, None)


def _count(session: Session, model: type) -> int:
    return session.scalar(select(func.count()).select_from(model)) or 0


def test_deleting_unit_cascades_in_database(
    db_session: Session,
    make_unit: Callable[..., Unit],
    make_topic: Callable[..., Topic],
    make_user: Callable[..., User],
) -> None:
    """Raw SQL DELETE proves ON DELETE CASCADE is in the schema, not just the ORM."""
    unit = make_unit(1)
    topic = make_topic(unit)
    db_session.add_all(
        [
            Formula(topic_id=topic.id, name="F", expression="x = 1"),
            PracticeQuestion(topic_id=topic.id, question_text="Q"),
            StudentProgress(user_id=make_user().id, topic_id=topic.id),
        ]
    )
    db_session.flush()

    db_session.execute(delete(Unit).where(Unit.id == unit.id))
    db_session.expire_all()

    for model in (Topic, Formula, PracticeQuestion, StudentProgress):
        assert _count(db_session, model) == 0, model.__name__
    assert _count(db_session, User) == 1  # users are never cascaded from syllabus rows


def test_deleting_user_removes_only_their_progress(
    db_session: Session,
    make_unit: Callable[..., Unit],
    make_topic: Callable[..., Topic],
    make_user: Callable[..., User],
) -> None:
    topic = make_topic(make_unit(1))
    alice, bob = make_user("alice@example.com"), make_user("bob@example.com")
    db_session.add_all(
        [
            StudentProgress(user_id=alice.id, topic_id=topic.id),
            StudentProgress(user_id=bob.id, topic_id=topic.id),
        ]
    )
    db_session.flush()

    db_session.delete(alice)
    db_session.flush()

    remaining = db_session.scalars(select(StudentProgress)).all()
    assert [p.user_id for p in remaining] == [bob.id]
    assert _count(db_session, Topic) == 1


def test_relationships_navigate_both_ways(
    db_session: Session, make_unit: Callable[..., Unit], make_topic: Callable[..., Topic]
) -> None:
    unit = make_unit(1)
    first, second = make_topic(unit, "A"), make_topic(unit, "B")
    db_session.expire_all()
    assert [t.title for t in unit.topics] == ["A", "B"]
    assert first.unit is unit
    assert second.unit.unit_number == 1
