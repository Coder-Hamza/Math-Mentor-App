from typing import Annotated

from pydantic import StringConstraints

from app.models.enums import Difficulty
from app.schemas.common import ORMReadModel, StrictInputModel

TopicTitle = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=200)]


class TopicCreate(StrictInputModel):
    unit_id: int
    title: TopicTitle
    description: str | None = None
    difficulty_level: Difficulty = Difficulty.MEDIUM


class TopicUpdate(StrictInputModel):
    unit_id: int | None = None
    title: TopicTitle | None = None
    description: str | None = None
    difficulty_level: Difficulty | None = None


class TopicRead(ORMReadModel):
    id: int
    unit_id: int
    title: str
    description: str | None
    difficulty_level: Difficulty
