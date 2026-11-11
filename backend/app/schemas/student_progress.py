from datetime import datetime
from typing import Annotated

from pydantic import Field

from app.schemas.common import ORMReadModel, StrictInputModel

Score = Annotated[float, Field(ge=0, le=100)]
Attempts = Annotated[int, Field(ge=0)]


class StudentProgressCreate(StrictInputModel):
    user_id: int
    topic_id: int
    score: Score = 0.0
    attempts: Attempts = 0
    last_attempted: datetime | None = None


class StudentProgressUpdate(StrictInputModel):
    score: Score | None = None
    attempts: Attempts | None = None
    last_attempted: datetime | None = None


class StudentProgressRead(ORMReadModel):
    id: int
    user_id: int
    topic_id: int
    score: float
    attempts: int
    last_attempted: datetime | None
