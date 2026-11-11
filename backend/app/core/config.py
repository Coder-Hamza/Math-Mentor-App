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

    gemini_api_key: SecretStr | None = None
    gemini_model: str = "gemini-2.5-flash"

    @property
    def cors_origin_list(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]


@lru_cache
def get_settings() -> Settings:
    """Return the cached settings instance (one parse per process)."""
    return Settings()
