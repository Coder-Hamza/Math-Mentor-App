from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.base import Base

if TYPE_CHECKING:
    from app.models.topic import Topic
    from app.models.user import User


class StudentProgress(Base):
    """Per-student, per-topic mastery. ``score`` is a percentage in [0, 100]."""

    __tablename__ = "student_progress"
    __table_args__ = (
        UniqueConstraint("user_id", "topic_id"),
        CheckConstraint("score >= 0 AND score <= 100", name="score_range"),
        CheckConstraint("attempts >= 0", name="attempts_non_negative"),
    )

    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    topic_id: Mapped[int] = mapped_column(ForeignKey("topics.id", ondelete="CASCADE"), index=True)
    score: Mapped[float] = mapped_column(default=0.0, server_default="0")
    attempts: Mapped[int] = mapped_column(default=0, server_default="0")
    last_attempted: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    user: Mapped[User] = relationship(back_populates="progress")
    topic: Mapped[Topic] = relationship(back_populates="progress")

    def __repr__(self) -> str:
        return f"StudentProgress(user_id={self.user_id!r}, topic_id={self.topic_id!r})"
