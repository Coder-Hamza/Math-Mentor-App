from app.models.enums import Difficulty, QuestionType
from app.schemas.common import NonEmptyStr, ORMReadModel, StrictInputModel


class PracticeQuestionCreate(StrictInputModel):
    topic_id: int
    question_text: NonEmptyStr
    difficulty: Difficulty = Difficulty.MEDIUM
    question_type: QuestionType = QuestionType.SHORT


class PracticeQuestionUpdate(StrictInputModel):
    topic_id: int | None = None
    question_text: NonEmptyStr | None = None
    difficulty: Difficulty | None = None
    question_type: QuestionType | None = None


class PracticeQuestionRead(ORMReadModel):
    id: int
    topic_id: int
    question_text: str
    difficulty: Difficulty
    question_type: QuestionType
