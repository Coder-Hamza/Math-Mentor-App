from typing import Annotated

from pydantic import BaseModel, ConfigDict, StringConstraints

NonEmptyStr = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1)]


class ORMReadModel(BaseModel):
    """Base for *Read schemas: built from ORM objects, immutable."""

    model_config = ConfigDict(from_attributes=True, frozen=True)


class StrictInputModel(BaseModel):
    """Base for *Create / *Update schemas: unknown fields are rejected."""

    model_config = ConfigDict(extra="forbid")
