"""Practice and progress API schemas."""

from typing import Annotated

from pydantic import BaseModel, ConfigDict, Field, StringConstraints

from app.models.enums import Difficulty, QuestionType
from app.schemas.common import StrictInputModel

MAX_ANSWER_LENGTH = 500
MAX_TIME_SECONDS = 24 * 60 * 60
MAX_PRACTICE_COUNT = 20
MAX_DB_INT = 2_147_483_647


class PracticeQuestionPublic(BaseModel):
    """A practice question as shown BEFORE answering: never contains the answer key."""

    model_config = ConfigDict(frozen=True)

    id: int
    topic_id: int
    topic_title: str
    unit_id: int
    unit_number: int
    unit_title: str
    question_text: str
    difficulty: Difficulty
    question_type: QuestionType
    options: list[str] | None = Field(description="The 4 choices of an MCQ, else null.")


class PracticeSubmitRequest(StrictInputModel):
    question_id: Annotated[int, Field(ge=1, le=MAX_DB_INT)]
    student_answer: Annotated[
        str, StringConstraints(strip_whitespace=True, min_length=1, max_length=MAX_ANSWER_LENGTH)
    ] = Field(description="MCQ: the option text or its letter (A-D). Otherwise the answer.")
    time_taken_seconds: Annotated[int, Field(ge=0, le=MAX_TIME_SECONDS)]


class PracticeSubmitResponse(BaseModel):
    is_correct: bool
    correct_answer: str
    explanation: str
    points_earned: int
    new_total_points: int
    streak: int = Field(description="Correct answers in a row, including this one.")
    encouragement: str
    already_solved: bool = Field(
        description="The student had already solved this question, so no points this time."
    )


class UnitProgress(BaseModel):
    unit_id: int
    unit_number: int
    unit_title: str
    topics_attempted: int
    topics_total: int = Field(description="Topics of the unit that have gradable questions.")
    avg_score: float = Field(description="Average accuracy (%) over attempted topics.")
    progress_percent: float = Field(
        description="Average accuracy (%) over ALL practisable topics (unattempted count as 0)."
    )


class ProgressSummary(BaseModel):
    total_points: int
    total_attempted: int
    total_correct: int
    accuracy_percent: float
    current_streak: int
    units_progress: list[UnitProgress]


class WeakTopic(BaseModel):
    topic_id: int
    topic_title: str
    unit_id: int
    unit_number: int
    unit_title: str
    attempts: int
    correct: int
    accuracy_percent: float
