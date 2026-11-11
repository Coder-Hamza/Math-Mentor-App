"""Shared FastAPI dependencies."""

from typing import Annotated

from fastapi import Depends, Path
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.core.errors import AuthenticationError
from app.core.tokens import InvalidTokenError, TokenType, decode_token
from app.database.session import get_db
from app.models import User

SessionDep = Annotated[Session, Depends(get_db)]

# Path ids are bounded to PostgreSQL INTEGER so oversized ids give 422, never a DB error.
IdPath = Annotated[int, Path(ge=1, le=2_147_483_647)]

bearer_scheme = HTTPBearer(
    auto_error=False,
    description="Paste the `access_token` returned by POST /api/v1/auth/login.",
)

_INVALID_TOKEN = "Invalid or expired token"  # noqa: S105 (message, not a secret)


def get_current_user(
    session: SessionDep,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)],
) -> User:
    """Resolve the active user from a Bearer access token, else raise 401."""
    if credentials is None:
        raise AuthenticationError("Not authenticated")
    try:
        user_id = decode_token(credentials.credentials, TokenType.ACCESS)
    except InvalidTokenError:
        raise AuthenticationError(_INVALID_TOKEN) from None
    user = session.get(User, user_id)
    if user is None or not user.is_active:
        raise AuthenticationError(_INVALID_TOKEN)
    return user


CurrentUser = Annotated[User, Depends(get_current_user)]
