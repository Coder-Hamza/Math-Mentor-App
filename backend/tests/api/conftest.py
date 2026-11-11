"""API test fixtures: a fresh app per test, wired to the rolled-back test-DB session."""

from collections.abc import Iterator

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from app.core.tokens import TokenType, create_token
from app.database.seed import SyllabusData, load_syllabus, seed_database
from app.database.session import get_db
from app.main import create_app
from app.models import User
from app.repositories import UserRepository
from app.schemas import UserCreate

PASSWORD = "correct-horse-battery"
EMAIL = "student@example.com"


@pytest.fixture
def app(db_session: Session) -> FastAPI:
    application = create_app()
    application.dependency_overrides[get_db] = lambda: db_session
    return application


@pytest.fixture
def client(app: FastAPI) -> Iterator[TestClient]:
    with TestClient(app) as test_client:
        yield test_client


@pytest.fixture
def user(db_session: Session) -> User:
    return UserRepository(db_session).create(
        UserCreate(email=EMAIL, name="Student", password=PASSWORD)
    )


@pytest.fixture
def auth_headers(user: User) -> dict[str, str]:
    return {"Authorization": f"Bearer {create_token(user.id, TokenType.ACCESS)}"}


@pytest.fixture
def seeded(db_session: Session) -> SyllabusData:
    data = load_syllabus()
    seed_database(db_session, data)
    return data


def assert_error(body: dict[str, object], code: str) -> None:
    """Every error uses the standard envelope."""
    assert set(body) == {"error"}
    error = body["error"]
    assert isinstance(error, dict)
    assert error["code"] == code
    assert isinstance(error["message"], str)
    assert error["message"]
