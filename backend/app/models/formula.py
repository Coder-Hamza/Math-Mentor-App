from typing import TYPE_CHECKING

from sqlalchemy import ForeignKey, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.base import Base

if TYPE_CHECKING:
    from app.models.topic import Topic


class Formula(Base):
    """A canonical formula. ``expression`` is SymPy-parseable (``lhs = rhs``) for verification."""

    __tablename__ = "formulas"
    __table_args__ = (UniqueConstraint("topic_id", "name"),)

    topic_id: Mapped[int] = mapped_column(ForeignKey("topics.id", ondelete="CASCADE"), index=True)
    name: Mapped[str] = mapped_column(String(200))
    expression: Mapped[str] = mapped_column(Text)
    description: Mapped[str | None] = mapped_column(Text)

    topic: Mapped[Topic] = relationship(back_populates="formulas")

    def __repr__(self) -> str:
        return f"Formula(id={self.id!r}, name={self.name!r})"
