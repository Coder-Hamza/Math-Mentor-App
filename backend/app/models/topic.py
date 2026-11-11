from typing import TYPE_CHECKING

from sqlalchemy import ForeignKey, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.base import Base
from app.models.enums import Difficulty, str_enum_column

if TYPE_CHECKING:
    from app.models.formula import Formula
    from app.models.practice_question import PracticeQuestion
    from app.models.student_progress import StudentProgress
    from app.models.unit import Unit


class Topic(Base):
    __tablename__ = "topics"
    __table_args__ = (UniqueConstraint("unit_id", "title"),)

    unit_id: Mapped[int] = mapped_column(ForeignKey("units.id", ondelete="CASCADE"), index=True)
    title: Mapped[str] = mapped_column(String(200))
    description: Mapped[str | None] = mapped_column(Text)
    difficulty_level: Mapped[Difficulty] = mapped_column(
        str_enum_column(Difficulty, "difficulty_level"), default=Difficulty.MEDIUM
    )

    unit: Mapped[Unit] = relationship(back_populates="topics")
    formulas: Mapped[list[Formula]] = relationship(
        back_populates="topic",
        cascade="all, delete-orphan",
        passive_deletes=True,
        order_by="Formula.id",
    )
    practice_questions: Mapped[list[PracticeQuestion]] = relationship(
        back_populates="topic",
        cascade="all, delete-orphan",
        passive_deletes=True,
        order_by="PracticeQuestion.id",
    )
    progress: Mapped[list[StudentProgress]] = relationship(
        back_populates="topic", cascade="all, delete-orphan", passive_deletes=True
    )

    def __repr__(self) -> str:
        return f"Topic(id={self.id!r}, title={self.title!r})"
