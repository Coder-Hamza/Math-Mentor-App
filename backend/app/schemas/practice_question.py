from typing import Annotated

from pydantic import Field

from app.models.enums import Difficulty, QuestionType
from app.schemas.common import NonEmptyStr, ORMReadModel, StrictInputModel

McqOptions = Annotated[list[NonEmptyStr], Field(min_length=4, max_length=4)]


class PracticeQuestionCreate(StrictInputModel):
    topic_id: int
    question_text: NonEmptyStr
    difficulty: Difficulty = Difficulty.MEDIUM
    question_type: QuestionType = QuestionType.SHORT
    options: McqOptions | None = None
    correct_answer: NonEmptyStr
    answer_explanation: NonEmptyStr


class PracticeQuestionUpdate(StrictInputModel):
    topic_id: int | None = None
    question_text: NonEmptyStr | None = None
    difficulty: Difficulty | None = None
    question_type: QuestionType | None = None
    options: McqOptions | None = None
    correct_answer: NonEmptyStr | None = None
    answer_explanation: NonEmptyStr | None = None


class PracticeQuestionRead(ORMReadModel):
    """What a student may see BEFORE answering: never the answer key."""

    id: int
    topic_id: int
    question_text: str
    difficulty: Difficulty
    question_type: QuestionType
    options: list[str] | None
