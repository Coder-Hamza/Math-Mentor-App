from datetime import datetime
from typing import Annotated

from pydantic import AfterValidator, EmailStr, Field, StringConstraints

from app.schemas.common import ORMReadModel, StrictInputModel

NormalizedEmail = Annotated[EmailStr, AfterValidator(str.lower)]
Name = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=100)]
Password = Annotated[str, Field(min_length=8, max_length=128)]


class UserCreate(StrictInputModel):
    email: NormalizedEmail
    name: Name
    password: Password


class UserUpdate(StrictInputModel):
    email: NormalizedEmail | None = None
    name: Name | None = None
    password: Password | None = None
    is_active: bool | None = None


class UserRead(ORMReadModel):
    """Public view of a user — never exposes the password hash."""

    id: int
    email: str
    name: str
    created_at: datetime
    is_active: bool
