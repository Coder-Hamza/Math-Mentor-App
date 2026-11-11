"""JWT access / refresh tokens (stateless, HS256).

Claims: ``sub`` (user id as string), ``type`` (access|refresh), ``iat``, ``exp``.
The ``type`` claim stops a long-lived refresh token being used as an access token.
"""

from datetime import UTC, datetime, timedelta
from enum import StrEnum

import jwt

from app.core.config import Settings, get_settings


class TokenType(StrEnum):
    ACCESS = "access"
    REFRESH = "refresh"


class InvalidTokenError(Exception):
    """Token is malformed, expired, has a bad signature, or is the wrong type."""


def create_token(
    user_id: int,
    token_type: TokenType,
    *,
    expires_delta: timedelta | None = None,
    settings: Settings | None = None,
) -> str:
    settings = settings or get_settings()
    if expires_delta is None:
        expires_delta = (
            timedelta(minutes=settings.access_token_expire_minutes)
            if token_type is TokenType.ACCESS
            else timedelta(days=settings.refresh_token_expire_days)
        )
    now = datetime.now(UTC)
    payload = {
        "sub": str(user_id),
        "type": token_type.value,
        "iat": now,
        "exp": now + expires_delta,
    }
    return jwt.encode(
        payload, settings.secret_key.get_secret_value(), algorithm=settings.jwt_algorithm
    )


def decode_token(token: str, expected_type: TokenType, *, settings: Settings | None = None) -> int:
    """Validate ``token`` and return the user id it was issued for."""
    settings = settings or get_settings()
    try:
        payload = jwt.decode(
            token,
            settings.secret_key.get_secret_value(),
            algorithms=[settings.jwt_algorithm],  # pinned: never trust the header's alg
            options={"require": ["sub", "type", "exp", "iat"]},
        )
    except jwt.PyJWTError as exc:
        raise InvalidTokenError(str(exc)) from exc
    if payload["type"] != expected_type.value:
        raise InvalidTokenError(f"expected a {expected_type.value} token")
    try:
        return int(payload["sub"])
    except (TypeError, ValueError) as exc:
        raise InvalidTokenError("invalid subject") from exc
