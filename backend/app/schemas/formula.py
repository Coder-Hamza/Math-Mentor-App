from typing import Annotated

from pydantic import StringConstraints

from app.schemas.common import NonEmptyStr, ORMReadModel, StrictInputModel

FormulaName = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=200)]


class FormulaCreate(StrictInputModel):
    topic_id: int
    name: FormulaName
    expression: NonEmptyStr
    description: str | None = None


class FormulaUpdate(StrictInputModel):
    topic_id: int | None = None
    name: FormulaName | None = None
    expression: NonEmptyStr | None = None
    description: str | None = None


class FormulaRead(ORMReadModel):
    id: int
    topic_id: int
    name: str
    expression: str
    description: str | None
