from collections.abc import Sequence

from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.models.unit import Unit
from app.repositories.base_repository import BaseRepository
from app.schemas.unit import UnitCreate, UnitUpdate


class UnitRepository(BaseRepository[Unit, UnitCreate, UnitUpdate]):
    model = Unit

    def get_by_number(self, unit_number: int) -> Unit | None:
        return self.session.scalars(select(Unit).where(Unit.unit_number == unit_number)).first()

    def list_ordered(self) -> Sequence[Unit]:
        """All units in syllabus order."""
        return self.session.scalars(select(Unit).order_by(Unit.unit_number)).all()

    def list_with_topics(self) -> Sequence[Unit]:
        """All units in syllabus order with topics eagerly loaded (no N+1 queries)."""
        stmt = select(Unit).options(selectinload(Unit.topics)).order_by(Unit.unit_number)
        return self.session.scalars(stmt).all()
