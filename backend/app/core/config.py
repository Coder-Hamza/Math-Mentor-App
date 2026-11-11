"""Application settings loaded from environment variables / ``backend/.env``."""

from functools import lru_cache
from pathlib import Path
from typing import Literal

from pydantic import SecretStr
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

    database_url: str
    test_database_url: str | None = None

    gemini_api_key: SecretStr | None = None
    gemini_model: str = "gemini-2.5-flash"


@lru_cache
def get_settings() -> Settings:
    """Return the cached settings instance (one parse per process)."""
    return Settings()
