from typing import Annotated

from pydantic import Field, StringConstraints

from app.schemas.common import ORMReadModel, StrictInputModel

UnitTitle = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=150)]
PositiveSmallInt = Annotated[int, Field(gt=0, le=32767)]


class UnitCreate(StrictInputModel):
    unit_number: PositiveSmallInt
    title: UnitTitle
    description: str | None = None
    page_number: PositiveSmallInt


class UnitUpdate(StrictInputModel):
    unit_number: PositiveSmallInt | None = None
    title: UnitTitle | None = None
    description: str | None = None
    page_number: PositiveSmallInt | None = None


class UnitRead(ORMReadModel):
    id: int
    unit_number: int
    title: str
    description: str | None
    page_number: int
