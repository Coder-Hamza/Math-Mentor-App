from typing import Literal

from pydantic import BaseModel, Field

from app.schemas.common import StrictInputModel
from app.schemas.user import NormalizedEmail


class LoginRequest(StrictInputModel):
    email: NormalizedEmail
    password: str = Field(min_length=1, max_length=128)


class RefreshRequest(StrictInputModel):
    refresh_token: str = Field(min_length=1)


class TokenPair(BaseModel):
    access_token: str
    refresh_token: str
    token_type: Literal["bearer"] = "bearer"  # noqa: S105 (OAuth2 token type)
    expires_in: int = Field(description="Access-token lifetime in seconds")
