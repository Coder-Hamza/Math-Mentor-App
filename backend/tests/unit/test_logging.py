"""LOG_LEVEL wiring and request logging."""

import logging
from collections.abc import Iterator

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app.core.config import Settings
from app.core.logging import APP_LOGGER, configure_logging
from app.main import create_app
from tests.fakes import make_settings


@pytest.fixture(autouse=True)
def restore_app_logger() -> Iterator[None]:
    logger = logging.getLogger(APP_LOGGER)
    level = logger.level
    yield
    logger.setLevel(level)


def _handlers() -> list[logging.Handler]:
    return [
        h
        for h in logging.getLogger(APP_LOGGER).handlers
        if h.get_name() == "mathmentor-app-handler"
    ]


@pytest.mark.parametrize("level", ["DEBUG", "INFO", "WARNING", "ERROR"])
def test_configure_logging_sets_level(level: str) -> None:
    logger = configure_logging(level)
    assert logger.name == "app"
    assert logger.level == getattr(logging, level)


def test_configure_logging_is_idempotent() -> None:
    configure_logging("INFO")
    configure_logging("DEBUG")
    assert len(_handlers()) == 1


def test_app_records_still_propagate_for_test_capture() -> None:
    assert configure_logging("INFO").propagate is True


def test_create_app_applies_log_level_from_settings() -> None:
    create_app(make_settings(log_level="WARNING"))
    assert logging.getLogger(APP_LOGGER).level == logging.WARNING
    create_app(make_settings(log_level="DEBUG"))
    assert logging.getLogger(APP_LOGGER).level == logging.DEBUG


def test_log_level_is_case_insensitive_and_validated() -> None:
    base = {"database_url": "postgresql+psycopg://u:p@h/db", "secret_key": "x" * 40}
    assert Settings(**base, log_level=" debug ").log_level == "DEBUG"
    with pytest.raises(ValidationError):
        Settings(**base, log_level="LOUD")


def test_requests_are_logged_without_query_string(caplog: pytest.LogCaptureFixture) -> None:
    client = TestClient(create_app(make_settings(log_level="INFO")))
    with caplog.at_level(logging.INFO, logger="app.request"):
        client.get("/health?token=secret-value")
    record = next(r for r in caplog.records if r.name == "app.request")
    assert record.levelno == logging.INFO
    assert record.getMessage().startswith("GET /health -> 200 (")
    assert "secret-value" not in caplog.text


def test_failed_requests_are_logged_as_500(caplog: pytest.LogCaptureFixture) -> None:
    app = create_app(make_settings(log_level="INFO"))

    @app.get("/explode")
    def explode() -> None:
        raise RuntimeError("boom")

    client = TestClient(app, raise_server_exceptions=False)
    with caplog.at_level(logging.INFO, logger="app.request"):
        assert client.get("/explode").status_code == 500
    assert any(
        r.name == "app.request" and r.getMessage().startswith("GET /explode -> 500")
        for r in caplog.records
    )
