"""Application settings loaded from environment variables / ``backend/.env``."""

from functools import lru_cache
from pathlib import Path
from typing import Literal

from pydantic import Field, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict

BACKEND_DIR = Path(__file__).resolve().parents[2]
PROJECT_ROOT = BACKEND_DIR.parent
SYLLABUS_DIR = PROJECT_ROOT / "syllabus"


class Settings(BaseSettings):
    """Typed configuration. Secrets are ``SecretStr`` so they never appear in logs/reprs."""

    model_config = SettingsConfigDict(
        env_file=BACKEND_DIR / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    app_name: str = "MathMentor AI"
    app_env: Literal["development", "test", "production"] = "development"
    debug: bool = False
    api_v1_prefix: str = "/api/v1"
    log_level: str = "INFO"
    # Comma-separated list. Browsers only — the native Android app does not send Origin.
    cors_origins: str = "http://localhost,http://10.0.2.2"

    database_url: str
    test_database_url: str | None = None

    # ---- Auth (JWT, HS256) ----
    secret_key: SecretStr = Field(min_length=32)
    jwt_algorithm: Literal["HS256"] = "HS256"
    access_token_expire_minutes: int = Field(default=60, gt=0)
    refresh_token_expire_days: int = Field(default=7, gt=0)

    # ---- Gemini (free tier) ----
    gemini_api_key: SecretStr | None = None
    gemini_model: str = "gemini-2.5-flash"
    gemini_timeout_seconds: float = Field(default=25, gt=0)  # per attempt
    gemini_max_retries: int = Field(default=2, ge=0, le=5)  # only for transient 5xx/network
    gemini_rate_limit_per_minute: int = Field(default=10, gt=0)
    gemini_rate_limit_per_day: int = Field(default=250, gt=0)

    # ---- Tutor pipeline ----
    # Hard cap for POST /tutor/ask: Gemini gets (tutor - sympy) seconds, SymPy gets the rest.
    tutor_timeout_seconds: float = Field(default=30, gt=0)
    sympy_timeout_seconds: float = Field(default=5, gt=0)

    @property
    def gemini_budget_seconds(self) -> float:
        return max(self.tutor_timeout_seconds - self.sympy_timeout_seconds, 1.0)

    @property
    def cors_origin_list(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]


@lru_cache
def get_settings() -> Settings:
    """Return the cached settings instance (one parse per process)."""
    return Settings()
