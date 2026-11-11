from datetime import UTC, datetime

import pytest
from pydantic import ValidationError

from app.models import Difficulty, QuestionType, User
from app.schemas import (
    FormulaCreate,
    FormulaUpdate,
    PracticeQuestionCreate,
    PracticeQuestionRead,
    StudentProgressCreate,
    StudentProgressUpdate,
    TopicCreate,
    TopicRead,
    UnitCreate,
    UnitUpdate,
    UserCreate,
    UserRead,
    UserUpdate,
)


class TestUserSchemas:
    def test_email_is_normalized_to_lowercase_and_name_stripped(self) -> None:
        user = UserCreate(email="Ali.Khan@Example.COM", name="  Ali  ", password="password1")
        assert user.email == "ali.khan@example.com"
        assert user.name == "Ali"

    @pytest.mark.parametrize("email", ["not-an-email", "a@", "@b.com", ""])
    def test_invalid_email_rejected(self, email: str) -> None:
        with pytest.raises(ValidationError):
            UserCreate(email=email, name="Ali", password="password1")

    @pytest.mark.parametrize("password", ["short", "x" * 129])
    def test_password_length_enforced(self, password: str) -> None:
        with pytest.raises(ValidationError):
            UserCreate(email="a@b.com", name="Ali", password=password)

    def test_unknown_fields_rejected(self) -> None:
        with pytest.raises(ValidationError):
            UserCreate.model_validate(
                {"email": "a@b.com", "name": "Ali", "password": "password1", "is_admin": True}
            )

    def test_update_tracks_only_explicitly_set_fields(self) -> None:
        update = UserUpdate(name="New Name")
        assert update.model_dump(exclude_unset=True) == {"name": "New Name"}

    def test_read_schema_never_exposes_password_hash(self) -> None:
        user = User(
            id=1,
            email="a@b.com",
            name="Ali",
            password_hash="scrypt$secret",
            created_at=datetime(2026, 1, 1, tzinfo=UTC),
            is_active=True,
        )
        data = UserRead.model_validate(user).model_dump()
        assert "password_hash" not in data
        assert "scrypt$secret" not in str(data)
        assert data["email"] == "a@b.com"


class TestUnitSchemas:
    def test_valid_unit(self) -> None:
        unit = UnitCreate(unit_number=1, title=" Complex Numbers ", page_number=1)
        assert unit.title == "Complex Numbers"
        assert unit.description is None

    @pytest.mark.parametrize("field", ["unit_number", "page_number"])
    @pytest.mark.parametrize("value", [0, -1])
    def test_numbers_must_be_positive(self, field: str, value: int) -> None:
        data = {"unit_number": 1, "title": "X", "page_number": 1} | {field: value}
        with pytest.raises(ValidationError):
            UnitCreate.model_validate(data)

    def test_blank_title_rejected(self) -> None:
        with pytest.raises(ValidationError):
            UnitCreate(unit_number=1, title="   ", page_number=1)

    def test_update_all_optional(self) -> None:
        assert UnitUpdate().model_dump(exclude_unset=True) == {}


class TestTopicSchemas:
    def test_default_difficulty_is_medium(self) -> None:
        assert TopicCreate(unit_id=1, title="Vectors").difficulty_level is Difficulty.MEDIUM

    def test_invalid_difficulty_rejected(self) -> None:
        with pytest.raises(ValidationError):
            TopicCreate.model_validate({"unit_id": 1, "title": "T", "difficulty_level": "extreme"})

    def test_read_schema_is_frozen(self) -> None:
        topic = TopicRead(
            id=1, unit_id=1, title="T", description=None, difficulty_level=Difficulty.EASY
        )
        with pytest.raises(ValidationError):
            topic.title = "changed"  # type: ignore[misc]


class TestFormulaAndQuestionSchemas:
    def test_formula_expression_required(self) -> None:
        with pytest.raises(ValidationError):
            FormulaCreate(topic_id=1, name="F", expression="  ")

    def test_formula_update_partial(self) -> None:
        assert FormulaUpdate(expression="x = 1").model_dump(exclude_unset=True) == {
            "expression": "x = 1"
        }

    def test_question_defaults(self) -> None:
        q = PracticeQuestionCreate(
            topic_id=1, question_text="Find i^2.", correct_answer="-1", answer_explanation="E"
        )
        assert (q.difficulty, q.question_type) == (Difficulty.MEDIUM, QuestionType.SHORT)

    def test_question_type_validated(self) -> None:
        with pytest.raises(ValidationError):
            PracticeQuestionCreate.model_validate(
                {
                    "topic_id": 1,
                    "question_text": "Q",
                    "question_type": "essay",
                    "correct_answer": "1",
                    "answer_explanation": "E",
                }
            )

    def test_answer_key_is_required(self) -> None:
        with pytest.raises(ValidationError):
            PracticeQuestionCreate(topic_id=1, question_text="Q")  # type: ignore[call-arg]

    @pytest.mark.parametrize("options", [["a", "b", "c"], ["a", "b", "c", "d", "e"]])
    def test_mcq_needs_exactly_four_options(self, options: list[str]) -> None:
        with pytest.raises(ValidationError):
            PracticeQuestionCreate(
                topic_id=1,
                question_text="Q",
                question_type=QuestionType.MCQ,
                options=options,
                correct_answer="a",
                answer_explanation="E",
            )

    def test_public_read_schema_never_exposes_the_answer(self) -> None:
        assert {"correct_answer", "answer_explanation"}.isdisjoint(
            PracticeQuestionRead.model_fields
        )


class TestStudentProgressSchemas:
    @pytest.mark.parametrize("score", [-0.1, 100.1])
    def test_score_must_be_percentage(self, score: float) -> None:
        with pytest.raises(ValidationError):
            StudentProgressCreate(user_id=1, topic_id=1, score=score)

    def test_attempts_non_negative(self) -> None:
        with pytest.raises(ValidationError):
            StudentProgressUpdate(attempts=-1)

    @pytest.mark.parametrize("score", [0, 55.5, 100])
    def test_boundary_scores_accepted(self, score: float) -> None:
        assert StudentProgressCreate(user_id=1, topic_id=1, score=score).score == score
