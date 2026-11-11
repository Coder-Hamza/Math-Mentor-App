from datetime import UTC, datetime, timedelta

import jwt
import pytest

from app.core.config import Settings, get_settings
from app.core.tokens import InvalidTokenError, TokenType, create_token, decode_token


def test_access_token_roundtrip() -> None:
    token = create_token(42, TokenType.ACCESS)
    assert decode_token(token, TokenType.ACCESS) == 42


def test_refresh_token_roundtrip() -> None:
    token = create_token(7, TokenType.REFRESH)
    assert decode_token(token, TokenType.REFRESH) == 7


def test_default_lifetimes_follow_settings() -> None:
    settings = get_settings()
    key = settings.secret_key.get_secret_value()
    for token_type, expected in (
        (TokenType.ACCESS, timedelta(minutes=settings.access_token_expire_minutes)),
        (TokenType.REFRESH, timedelta(days=settings.refresh_token_expire_days)),
    ):
        claims = jwt.decode(create_token(1, token_type), key, algorithms=["HS256"])
        assert claims["exp"] - claims["iat"] == int(expected.total_seconds())
        assert claims["sub"] == "1"
        assert claims["type"] == token_type.value


@pytest.mark.parametrize(
    ("issued", "expected"),
    [(TokenType.REFRESH, TokenType.ACCESS), (TokenType.ACCESS, TokenType.REFRESH)],
)
def test_wrong_token_type_rejected(issued: TokenType, expected: TokenType) -> None:
    with pytest.raises(InvalidTokenError, match=f"expected a {expected.value} token"):
        decode_token(create_token(1, issued), expected)


def test_expired_token_rejected() -> None:
    token = create_token(1, TokenType.ACCESS, expires_delta=timedelta(seconds=-1))
    with pytest.raises(InvalidTokenError):
        decode_token(token, TokenType.ACCESS)


def test_token_signed_with_other_key_rejected() -> None:
    other = Settings(database_url="postgresql+psycopg://u:p@h/db", secret_key="x" * 40)
    token = create_token(1, TokenType.ACCESS, settings=other)
    with pytest.raises(InvalidTokenError):
        decode_token(token, TokenType.ACCESS)


def test_alg_none_token_rejected() -> None:
    now = datetime.now(UTC)
    unsigned = jwt.encode(
        {"sub": "1", "type": "access", "iat": now, "exp": now + timedelta(minutes=5)},
        key=None,
        algorithm="none",
    )
    with pytest.raises(InvalidTokenError):
        decode_token(unsigned, TokenType.ACCESS)


@pytest.mark.parametrize("token", ["", "garbage", "a.b.c"])
def test_malformed_token_rejected(token: str) -> None:
    with pytest.raises(InvalidTokenError):
        decode_token(token, TokenType.ACCESS)


def _signed(claims: dict[str, object]) -> str:
    return jwt.encode(claims, get_settings().secret_key.get_secret_value(), algorithm="HS256")


def test_missing_required_claim_rejected() -> None:
    now = datetime.now(UTC)
    token = _signed({"sub": "1", "iat": now, "exp": now + timedelta(minutes=5)})  # no type
    with pytest.raises(InvalidTokenError):
        decode_token(token, TokenType.ACCESS)


def test_non_numeric_subject_rejected() -> None:
    now = datetime.now(UTC)
    token = _signed({"sub": "abc", "type": "access", "iat": now, "exp": now + timedelta(minutes=5)})
    with pytest.raises(InvalidTokenError, match="invalid subject"):
        decode_token(token, TokenType.ACCESS)


def test_secret_key_must_be_long() -> None:
    with pytest.raises(ValueError, match="at least 32"):
        Settings(database_url="postgresql+psycopg://u:p@h/db", secret_key="short")


def test_cors_origin_list_parsing() -> None:
    settings = Settings(
        database_url="postgresql+psycopg://u:p@h/db",
        secret_key="x" * 40,
        cors_origins=" http://localhost , http://10.0.2.2,, ",
    )
    assert settings.cors_origin_list == ["http://localhost", "http://10.0.2.2"]
