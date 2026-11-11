from sqlalchemy.orm import Session

from app.core.config import SYLLABUS_DIR, Settings, get_settings
from app.database.session import get_db, get_engine


def test_settings_loaded_and_cached() -> None:
    settings = get_settings()
    assert settings is get_settings()
    assert settings.database_url.startswith("postgresql+psycopg://")


def test_secrets_are_masked_in_repr() -> None:
    settings = Settings(database_url="postgresql+psycopg://u:p@h/db", gemini_api_key="real-key")
    assert "real-key" not in repr(settings)
    assert settings.gemini_api_key is not None
    assert settings.gemini_api_key.get_secret_value() == "real-key"


def test_syllabus_dir_points_at_repo_folder() -> None:
    assert (SYLLABUS_DIR / "chapters" / "units.json").is_file()


def test_engine_is_lazy_singleton() -> None:
    assert get_engine() is get_engine()


def test_get_db_yields_session_and_closes() -> None:
    gen = get_db()
    session = next(gen)
    assert isinstance(session, Session)
    gen.close()
