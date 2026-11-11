import pytest

from app.core.security import hash_password, verify_password


def test_hash_is_not_plaintext_and_verifies() -> None:
    hashed = hash_password("s3cret-pass")
    assert "s3cret-pass" not in hashed
    assert hashed.startswith("scrypt$")
    assert verify_password("s3cret-pass", hashed)


def test_wrong_password_does_not_verify() -> None:
    assert not verify_password("wrong", hash_password("right-password"))


def test_same_password_gets_unique_salt() -> None:
    assert hash_password("same-password") != hash_password("same-password")


def test_unicode_password_roundtrip() -> None:
    hashed = hash_password("ریاضی-123-پاس")
    assert verify_password("ریاضی-123-پاس", hashed)


@pytest.mark.parametrize(
    "stored",
    [
        "",
        "not-a-hash",
        "bcrypt$16384$8$1$c2FsdA==$aGFzaA==",  # wrong algorithm
        "scrypt$abc$8$1$c2FsdA==$aGFzaA==",  # non-integer parameter
        "scrypt$16384$8$1$!!!$aGFzaA==",  # invalid base64
        "scrypt$16384$8",  # too few parts
    ],
)
def test_malformed_hash_never_verifies(stored: str) -> None:
    assert verify_password("anything", stored) is False
