from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.base import Base

if TYPE_CHECKING:
    from app.models.practice_question import PracticeQuestion
    from app.models.user import User


class PracticeAttempt(Base):
    """One submitted answer. The log behind streaks and "points only once per question"."""

    __tablename__ = "practice_attempts"
    __table_args__ = (
        CheckConstraint("points_earned >= 0", name="points_non_negative"),
        CheckConstraint("time_taken_seconds >= 0", name="time_non_negative"),
    )

    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    question_id: Mapped[int] = mapped_column(
        ForeignKey("practice_questions.id", ondelete="CASCADE"), index=True
    )
    is_correct: Mapped[bool]
    points_earned: Mapped[int] = mapped_column(default=0)
    time_taken_seconds: Mapped[int]
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    user: Mapped[User] = relationship(back_populates="attempts")
    question: Mapped[PracticeQuestion] = relationship(back_populates="attempts")

    def __repr__(self) -> str:
        return (
            f"PracticeAttempt(user_id={self.user_id!r}, question_id={self.question_id!r}, "
            f"is_correct={self.is_correct!r})"
        )
