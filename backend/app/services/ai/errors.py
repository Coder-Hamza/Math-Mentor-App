"""AI-service errors. They subclass ``AppError`` so the API maps them to the error envelope.

Messages are student-facing: short, friendly, and free of internal details.
"""

from app.core.errors import AppError


class AIServiceError(AppError):
    status_code = 503
    code = "ai_unavailable"

    def __init__(
        self, message: str = "The AI tutor is unavailable right now. Please try again."
    ) -> None:
        super().__init__(message)


class AIUnavailableError(AIServiceError):
    """Gemini is down, unreachable, or rejected the request."""


class AINotConfiguredError(AIServiceError):
    code = "ai_not_configured"

    def __init__(self) -> None:
        super().__init__("The AI tutor is not configured on this server.")


class AIModelUnavailableError(AIServiceError):
    """Every configured model (primary and fallback) returned HTTP 404."""

    code = "ai_model_unavailable"

    def __init__(self) -> None:
        super().__init__(
            "The AI tutor's language model is not available right now. Please try again later."
        )


class AIQuotaExceededError(AIServiceError):
    status_code = 429
    code = "ai_quota_exceeded"

    def __init__(self, retry_after_seconds: int = 60) -> None:
        AppError.__init__(
            self,
            "The AI tutor is very busy right now (free usage limit reached). "
            f"Please try again in about {retry_after_seconds} seconds.",
            headers={"Retry-After": str(retry_after_seconds)},
        )
        self.retry_after_seconds = retry_after_seconds


class AITimeoutError(AIServiceError):
    status_code = 504
    code = "ai_timeout"

    def __init__(self) -> None:
        super().__init__("The AI tutor took too long to answer. Please try again.")


class AIBadResponseError(AIServiceError):
    status_code = 502
    code = "ai_bad_response"

    def __init__(self) -> None:
        super().__init__("The AI tutor returned an empty answer. Please try again.")
