"""Generic CRUD repository.

Repositories ``flush`` but never ``commit``: the caller (service / request scope) owns the
transaction, so several repository calls can be committed or rolled back together.
"""

from collections.abc import Sequence

from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.database.base import Base

MAX_PAGE_SIZE = 500


class BaseRepository[ModelT: Base, CreateT: BaseModel, UpdateT: BaseModel]:
    model: type[ModelT]  # set by each subclass, e.g. ``model = User``

    def __init__(self, session: Session) -> None:
        self.session = session

    def get(self, id_: int) -> ModelT | None:
        return self.session.get(self.model, id_)

    def get_multi(self, *, offset: int = 0, limit: int = 100) -> Sequence[ModelT]:
        if offset < 0 or not 0 < limit <= MAX_PAGE_SIZE:
            raise ValueError(f"offset must be >= 0 and limit in 1..{MAX_PAGE_SIZE}")
        stmt = select(self.model).order_by(self.model.id).offset(offset).limit(limit)
        return self.session.scalars(stmt).all()

    def count(self) -> int:
        return self.session.scalar(select(func.count()).select_from(self.model)) or 0

    def create(self, data: CreateT) -> ModelT:
        return self._add(self.model(**data.model_dump()))

    def update(self, obj: ModelT, data: UpdateT) -> ModelT:
        """Apply only the fields the caller explicitly set (``exclude_unset``)."""
        for field, value in data.model_dump(exclude_unset=True).items():
            setattr(obj, field, value)
        self.session.flush()
        self.session.refresh(obj)
        return obj

    def delete(self, obj: ModelT) -> None:
        self.session.delete(obj)
        self.session.flush()

    def _add(self, obj: ModelT) -> ModelT:
        self.session.add(obj)
        self.session.flush()
        self.session.refresh(obj)
        return obj
