from typing import TYPE_CHECKING

from sqlalchemy import JSON, CheckConstraint, ForeignKey, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.base import Base
from app.models.enums import Difficulty, QuestionType, str_enum_column

if TYPE_CHECKING:
    from app.models.practice_attempt import PracticeAttempt
    from app.models.topic import Topic


class PracticeQuestion(Base):
    """A practice question with its answer key.

    ``correct_answer`` and ``answer_explanation`` are secret until the student submits: no
    endpoint returns them before ``POST /practice/submit``. For MCQs ``options`` holds the
    four choices and ``correct_answer`` is the text of the right one; other types have no
    options.
    """

    __tablename__ = "practice_questions"
    __table_args__ = (
        UniqueConstraint("topic_id", "question_text"),
        CheckConstraint("(question_type = 'mcq') = (options IS NOT NULL)", name="mcq_has_options"),
    )

    topic_id: Mapped[int] = mapped_column(ForeignKey("topics.id", ondelete="CASCADE"), index=True)
    question_text: Mapped[str] = mapped_column(Text)
    difficulty: Mapped[Difficulty] = mapped_column(
        str_enum_column(Difficulty, "difficulty"), default=Difficulty.MEDIUM
    )
    question_type: Mapped[QuestionType] = mapped_column(
        str_enum_column(QuestionType, "question_type"), default=QuestionType.SHORT
    )
    options: Mapped[list[str] | None] = mapped_column(JSON(none_as_null=True))
    correct_answer: Mapped[str] = mapped_column(Text)
    answer_explanation: Mapped[str] = mapped_column(Text)

    topic: Mapped[Topic] = relationship(back_populates="practice_questions")
    attempts: Mapped[list[PracticeAttempt]] = relationship(
        back_populates="question", cascade="all, delete-orphan", passive_deletes=True
    )

    @property
    def is_gradable(self) -> bool:
        """Proofs need a human (or AI) reader; questions without an answer key can't be graded."""
        return self.question_type is not QuestionType.PROOF and bool(self.correct_answer.strip())

    def __repr__(self) -> str:
        return f"PracticeQuestion(id={self.id!r}, topic_id={self.topic_id!r})"
