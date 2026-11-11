"""Domain errors. API handlers translate these into the standard error envelope."""

from collections.abc import Mapping


class AppError(Exception):
    status_code = 400
    code = "bad_request"

    def __init__(self, message: str, *, headers: Mapping[str, str] | None = None) -> None:
        super().__init__(message)
        self.message = message
        self.headers = dict(headers or {})


class NotFoundError(AppError):
    status_code = 404
    code = "not_found"


class ConflictError(AppError):
    status_code = 409
    code = "conflict"


class AuthenticationError(AppError):
    status_code = 401
    code = "not_authenticated"

    def __init__(self, message: str) -> None:
        super().__init__(message, headers={"WWW-Authenticate": "Bearer"})
