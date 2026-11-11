"""Password hashing with the standard-library scrypt KDF (no extra dependency).

Stored format: ``scrypt$<n>$<r>$<p>$<salt_b64>$<hash_b64>`` so parameters can be raised later
without invalidating existing hashes.
"""

import base64
import hashlib
import hmac
import secrets

_ALGORITHM = "scrypt"
_N = 2**14
_R = 8
_P = 1
_SALT_BYTES = 16
_KEY_BYTES = 64


def _b64encode(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).decode("ascii")


def _b64decode(text: str) -> bytes:
    return base64.urlsafe_b64decode(text.encode("ascii"))


def hash_password(password: str) -> str:
    """Hash ``password`` with a fresh random salt."""
    salt = secrets.token_bytes(_SALT_BYTES)
    digest = hashlib.scrypt(password.encode("utf-8"), salt=salt, n=_N, r=_R, p=_P, dklen=_KEY_BYTES)
    return f"{_ALGORITHM}${_N}${_R}${_P}${_b64encode(salt)}${_b64encode(digest)}"


def verify_password(password: str, stored_hash: str) -> bool:
    """Return True if ``password`` matches ``stored_hash``. Malformed hashes never match."""
    parts = stored_hash.split("$")
    if len(parts) != 6 or parts[0] != _ALGORITHM:
        return False
    try:
        n, r, p = (int(value) for value in parts[1:4])
        salt = _b64decode(parts[4])
        expected = _b64decode(parts[5])
        actual = hashlib.scrypt(
            password.encode("utf-8"), salt=salt, n=n, r=r, p=p, dklen=len(expected)
        )
    except ValueError:
        return False
    return hmac.compare_digest(actual, expected)
