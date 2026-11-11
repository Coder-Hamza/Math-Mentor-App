from typing import TYPE_CHECKING

from sqlalchemy import CheckConstraint, SmallInteger, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.base import Base

if TYPE_CHECKING:
    from app.models.topic import Topic


class Unit(Base):
    """A textbook unit (chapter) of the Sindh Board HSC-I Mathematics syllabus."""

    __tablename__ = "units"
    __table_args__ = (
        CheckConstraint("unit_number > 0", name="unit_number_positive"),
        CheckConstraint("page_number > 0", name="page_number_positive"),
    )

    unit_number: Mapped[int] = mapped_column(SmallInteger, unique=True)
    title: Mapped[str] = mapped_column(String(150))
    description: Mapped[str | None] = mapped_column(Text)
    page_number: Mapped[int] = mapped_column(SmallInteger)

    topics: Mapped[list[Topic]] = relationship(
        back_populates="unit",
        cascade="all, delete-orphan",
        passive_deletes=True,
        order_by="Topic.id",
    )

    def __repr__(self) -> str:
        return f"Unit(unit_number={self.unit_number!r}, title={self.title!r})"
