"""PostgreSQL integration fixtures.

* The schema is built with the real Alembic migrations (not ``create_all``), so the
  migrations themselves are under test.
* Each test runs inside a transaction that is rolled back, so tests are isolated and the
  test database is left clean.
* Refuses to run against any database whose name does not contain ``test``.
"""

from collections.abc import Callable, Iterator
from typing import Any

import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import Engine, create_engine, make_url
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import Session

from app.core.config import BACKEND_DIR, get_settings
from app.models import Difficulty, PracticeQuestion, QuestionType, Topic, Unit, User


def alembic_config(url: str) -> Config:
    config = Config(str(BACKEND_DIR / "alembic.ini"))
    config.attributes["database_url"] = url
    config.attributes["configure_logger"] = False
    return config


@pytest.fixture(scope="session")
def test_database_url() -> str:
    settings = get_settings()
    url = settings.test_database_url
    if not url:
        pytest.skip("TEST_DATABASE_URL is not configured")
    database = make_url(url).database or ""
    if "test" not in database or url == settings.database_url:
        pytest.fail(f"refusing to run destructive tests against database {database!r}")
    return url


@pytest.fixture(scope="session")
def migrated_engine(test_database_url: str) -> Iterator[Engine]:
    engine = create_engine(test_database_url)
    try:
        engine.connect().close()
    except OperationalError as exc:
        pytest.skip(f"test database unavailable: {exc}")
    config = alembic_config(test_database_url)
    command.downgrade(config, "base")  # clean slate even if a previous run aborted
    command.upgrade(config, "head")
    yield engine
    command.downgrade(config, "base")
    engine.dispose()


@pytest.fixture
def db_session(migrated_engine: Engine) -> Iterator[Session]:
    connection = migrated_engine.connect()
    transaction = connection.begin()
    session = Session(bind=connection, join_transaction_mode="create_savepoint")
    try:
        yield session
    finally:
        session.close()
        transaction.rollback()
        connection.close()


# ------------------------------------------------------------------ factories


@pytest.fixture
def make_unit(db_session: Session) -> Callable[..., Unit]:
    def factory(unit_number: int = 1, **kwargs: Any) -> Unit:
        values = {"title": f"Unit {unit_number}", "page_number": 1} | kwargs
        unit = Unit(unit_number=unit_number, **values)
        db_session.add(unit)
        db_session.flush()
        return unit

    return factory


@pytest.fixture
def make_topic(db_session: Session) -> Callable[..., Topic]:
    def factory(unit: Unit, title: str = "Topic", **kwargs: Any) -> Topic:
        values = {"difficulty_level": Difficulty.MEDIUM} | kwargs
        topic = Topic(unit_id=unit.id, title=title, **values)
        db_session.add(topic)
        db_session.flush()
        return topic

    return factory


@pytest.fixture
def make_user(db_session: Session) -> Callable[..., User]:
    def factory(email: str = "student@example.com", **kwargs: Any) -> User:
        values = {"name": "Student", "password_hash": "scrypt$x"} | kwargs
        user = User(email=email, **values)
        db_session.add(user)
        db_session.flush()
        return user

    return factory


@pytest.fixture
def make_question(db_session: Session) -> Callable[..., PracticeQuestion]:
    def factory(topic: Topic, text: str = "Q?", **kwargs: Any) -> PracticeQuestion:
        values: dict[str, Any] = {
            "difficulty": Difficulty.EASY,
            "question_type": QuestionType.SHORT,
            "correct_answer": "3/2",
            "answer_explanation": "Because.",
        } | kwargs
        question = PracticeQuestion(topic_id=topic.id, question_text=text, **values)
        db_session.add(question)
        db_session.flush()
        return question

    return factory
