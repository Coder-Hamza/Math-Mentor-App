from typing import TYPE_CHECKING

from sqlalchemy import ForeignKey, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.base import Base
from app.models.enums import Difficulty, QuestionType, str_enum_column

if TYPE_CHECKING:
    from app.models.topic import Topic


class PracticeQuestion(Base):
    __tablename__ = "practice_questions"
    __table_args__ = (UniqueConstraint("topic_id", "question_text"),)

    topic_id: Mapped[int] = mapped_column(ForeignKey("topics.id", ondelete="CASCADE"), index=True)
    question_text: Mapped[str] = mapped_column(Text)
    difficulty: Mapped[Difficulty] = mapped_column(
        str_enum_column(Difficulty, "difficulty"), default=Difficulty.MEDIUM
    )
    question_type: Mapped[QuestionType] = mapped_column(
        str_enum_column(QuestionType, "question_type"), default=QuestionType.SHORT
    )

    topic: Mapped[Topic] = relationship(back_populates="practice_questions")

    def __repr__(self) -> str:
        return f"PracticeQuestion(id={self.id!r}, topic_id={self.topic_id!r})"
