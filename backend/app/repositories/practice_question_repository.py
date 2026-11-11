from collections.abc import Sequence

from sqlalchemy import ColumnElement, func, select
from sqlalchemy.orm import contains_eager

from app.models import PracticeQuestion, QuestionType, Topic, Unit
from app.repositories.base_repository import BaseRepository
from app.schemas.practice_question import PracticeQuestionCreate, PracticeQuestionUpdate


def gradable_clause() -> ColumnElement[bool]:
    """SQL twin of ``PracticeQuestion.is_gradable``."""
    return (PracticeQuestion.question_type != QuestionType.PROOF) & (
        func.trim(PracticeQuestion.correct_answer) != ""
    )


class PracticeQuestionRepository(
    BaseRepository[PracticeQuestion, PracticeQuestionCreate, PracticeQuestionUpdate]
):
    model = PracticeQuestion

    def get_with_topic(self, question_id: int) -> PracticeQuestion | None:
        """Question with its topic and unit loaded in the same query."""
        stmt = (
            select(PracticeQuestion)
            .join(PracticeQuestion.topic)
            .join(Topic.unit)
            .options(contains_eager(PracticeQuestion.topic).contains_eager(Topic.unit))
            .where(PracticeQuestion.id == question_id)
        )
        return self.session.scalars(stmt).first()

    def random_gradable(
        self, *, count: int, unit_id: int | None = None
    ) -> Sequence[PracticeQuestion]:
        """Up to ``count`` random gradable questions (optionally from one unit)."""
        stmt = (
            select(PracticeQuestion)
            .join(PracticeQuestion.topic)
            .join(Topic.unit)
            .options(contains_eager(PracticeQuestion.topic).contains_eager(Topic.unit))
            .where(gradable_clause())
            .order_by(func.random())
            .limit(count)
        )
        if unit_id is not None:
            stmt = stmt.where(Unit.id == unit_id)
        return self.session.scalars(stmt).all()
