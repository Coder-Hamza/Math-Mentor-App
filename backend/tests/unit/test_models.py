"""Model metadata tests (no database needed)."""

import pytest
from sqlalchemy import CheckConstraint, Enum, UniqueConstraint
from sqlalchemy.orm import configure_mappers

from app.database.base import Base
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


def test_all_mappers_configure() -> None:
    configure_mappers()


def test_expected_tables_registered() -> None:
    assert set(Base.metadata.tables) == {
        "users",
        "units",
        "topics",
        "formulas",
        "practice_questions",
        "student_progress",
    }


@pytest.mark.parametrize(
    ("model", "columns"),
    [
        (User, {"id", "email", "password_hash", "name", "created_at", "is_active"}),
        (Unit, {"id", "unit_number", "title", "description", "page_number"}),
        (Topic, {"id", "unit_id", "title", "description", "difficulty_level"}),
        (Formula, {"id", "topic_id", "name", "expression", "description"}),
        (PracticeQuestion, {"id", "topic_id", "question_text", "difficulty", "question_type"}),
        (
            StudentProgress,
            {"id", "user_id", "topic_id", "score", "attempts", "last_attempted"},
        ),
    ],
)
def test_model_columns_match_spec(model: type[Base], columns: set[str]) -> None:
    assert set(model.__table__.columns.keys()) == columns


@pytest.mark.parametrize(
    ("model", "fk_column", "target"),
    [
        (Topic, "unit_id", "units.id"),
        (Formula, "topic_id", "topics.id"),
        (PracticeQuestion, "topic_id", "topics.id"),
        (StudentProgress, "user_id", "users.id"),
        (StudentProgress, "topic_id", "topics.id"),
    ],
)
def test_foreign_keys_cascade_on_delete(model: type[Base], fk_column: str, target: str) -> None:
    (fk,) = model.__table__.columns[fk_column].foreign_keys
    assert fk.target_fullname == target
    assert fk.ondelete == "CASCADE"
    assert model.__table__.columns[fk_column].index is True


def _unique_sets(model: type[Base]) -> set[frozenset[str]]:
    return {
        frozenset(c.name for c in constraint.columns)
        for constraint in model.__table__.constraints
        if isinstance(constraint, UniqueConstraint)
    }


def test_natural_key_uniqueness() -> None:
    assert frozenset({"unit_number"}) in _unique_sets(Unit)
    assert frozenset({"unit_id", "title"}) in _unique_sets(Topic)
    assert frozenset({"topic_id", "name"}) in _unique_sets(Formula)
    assert frozenset({"topic_id", "question_text"}) in _unique_sets(PracticeQuestion)
    assert frozenset({"user_id", "topic_id"}) in _unique_sets(StudentProgress)
    assert User.__table__.columns["email"].unique is True


def test_progress_check_constraints() -> None:
    texts = {
        str(c.sqltext)
        for c in StudentProgress.__table__.constraints
        if isinstance(c, CheckConstraint)
    }
    assert "score >= 0 AND score <= 100" in texts
    assert "attempts >= 0" in texts


@pytest.mark.parametrize(
    ("column", "enum_cls"),
    [
        (Topic.__table__.c.difficulty_level, Difficulty),
        (PracticeQuestion.__table__.c.difficulty, Difficulty),
        (PracticeQuestion.__table__.c.question_type, QuestionType),
    ],
)
def test_enum_columns_store_lowercase_values(column: object, enum_cls: type) -> None:
    col_type = column.type  # type: ignore[attr-defined]
    assert isinstance(col_type, Enum)
    assert col_type.native_enum is False
    assert list(col_type.enums) == [member.value for member in enum_cls]


def test_python_side_defaults() -> None:
    assert Topic.__table__.c.difficulty_level.default.arg is Difficulty.MEDIUM
    assert StudentProgress.__table__.c.score.default.arg == 0.0
    assert StudentProgress.__table__.c.attempts.default.arg == 0


def test_reprs_are_informative_and_safe() -> None:
    user = User(id=7, email="a@b.com", name="Ali", password_hash="scrypt$SECRET")
    assert "SECRET" not in repr(user)
    assert repr(user) == "User(id=7, email='a@b.com')"
    assert repr(Unit(unit_number=1, title="Complex Numbers")) == (
        "Unit(unit_number=1, title='Complex Numbers')"
    )
    assert repr(Topic(id=1, title="Vectors")) == "Topic(id=1, title='Vectors')"
    assert repr(Formula(id=2, name="Dot")) == "Formula(id=2, name='Dot')"
    assert repr(PracticeQuestion(id=3, topic_id=1)) == "PracticeQuestion(id=3, topic_id=1)"
    assert repr(StudentProgress(user_id=1, topic_id=2)) == "StudentProgress(user_id=1, topic_id=2)"
