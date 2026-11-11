"""Content endpoints: units, topics, formulas, questions."""

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from app.database.seed import SyllabusData
from app.repositories import TopicRepository, UnitRepository
from tests.api.conftest import assert_error

pytestmark = pytest.mark.integration

API = "/api/v1"
PROTECTED_PATHS = [
    "/units/",
    "/units/1",
    "/units/1/topics",
    "/topics/1",
    "/topics/1/formulas",
    "/topics/1/questions",
]


def _unit_id(session: Session, number: int) -> int:
    unit = UnitRepository(session).get_by_number(number)
    assert unit is not None
    return unit.id


def _topic_id(session: Session, unit_number: int, title: str) -> int:
    topic = TopicRepository(session).get_by_title(_unit_id(session, unit_number), title)
    assert topic is not None
    return topic.id


@pytest.mark.parametrize("path", PROTECTED_PATHS)
def test_content_requires_authentication(client: TestClient, path: str) -> None:
    response = client.get(API + path)
    assert response.status_code == 401
    assert_error(response.json(), "not_authenticated")


# ------------------------------------------------------------------ units


def test_list_units_in_syllabus_order(
    client: TestClient, auth_headers: dict[str, str], seeded: SyllabusData
) -> None:
    response = client.get(f"{API}/units/", headers=auth_headers)
    assert response.status_code == 200
    units = response.json()
    assert [u["unit_number"] for u in units] == list(range(1, 13))
    assert units[0]["title"] == "Complex Numbers"
    assert units[11]["page_number"] == 337
    assert set(units[0]) == {"id", "unit_number", "title", "description", "page_number"}


def test_list_units_empty_database(client: TestClient, auth_headers: dict[str, str]) -> None:
    response = client.get(f"{API}/units/", headers=auth_headers)
    assert response.status_code == 200
    assert response.json() == []


def test_get_unit(
    client: TestClient, auth_headers: dict[str, str], seeded: SyllabusData, db_session: Session
) -> None:
    unit_id = _unit_id(db_session, 3)
    response = client.get(f"{API}/units/{unit_id}", headers=auth_headers)
    assert response.status_code == 200
    assert response.json()["title"] == "Vectors"
    assert response.json()["page_number"] == 74


def test_list_unit_topics(
    client: TestClient, auth_headers: dict[str, str], seeded: SyllabusData, db_session: Session
) -> None:
    unit_id = _unit_id(db_session, 1)
    response = client.get(f"{API}/units/{unit_id}/topics", headers=auth_headers)
    assert response.status_code == 200
    titles = [t["title"] for t in response.json()]
    expected = [t.title for t in seeded.topics if t.unit_number == 1]
    assert titles == expected
    assert all(t["unit_id"] == unit_id for t in response.json())


@pytest.mark.parametrize("suffix", ["", "/topics"])
def test_missing_unit_is_404(client: TestClient, auth_headers: dict[str, str], suffix: str) -> None:
    response = client.get(f"{API}/units/999999{suffix}", headers=auth_headers)
    assert response.status_code == 404
    assert_error(response.json(), "not_found")
    assert "999999" in response.json()["error"]["message"]


# ------------------------------------------------------------------ topics


def test_get_topic(
    client: TestClient, auth_headers: dict[str, str], seeded: SyllabusData, db_session: Session
) -> None:
    topic_id = _topic_id(db_session, 3, "Scalar (Dot) Product")
    response = client.get(f"{API}/topics/{topic_id}", headers=auth_headers)
    assert response.status_code == 200
    body = response.json()
    assert body["title"] == "Scalar (Dot) Product"
    assert body["difficulty_level"] == "medium"


def test_list_topic_formulas(
    client: TestClient, auth_headers: dict[str, str], seeded: SyllabusData, db_session: Session
) -> None:
    topic_id = _topic_id(db_session, 10, "Sum and Difference Formulas")
    response = client.get(f"{API}/topics/{topic_id}/formulas", headers=auth_headers)
    assert response.status_code == 200
    expected = [
        f.name
        for f in seeded.formulas
        if (f.unit_number, f.topic) == (10, "Sum and Difference Formulas")
    ]
    assert [f["name"] for f in response.json()] == expected  # stable insertion order
    assert set(response.json()[0]) == {"id", "topic_id", "name", "expression", "description"}


def test_list_topic_questions(
    client: TestClient, auth_headers: dict[str, str], seeded: SyllabusData, db_session: Session
) -> None:
    topic_id = _topic_id(db_session, 9, "Optimization by Corner Point Method")
    response = client.get(f"{API}/topics/{topic_id}/questions", headers=auth_headers)
    assert response.status_code == 200
    (question,) = response.json()
    assert question["question_text"].startswith("Maximize Z = 3x + 2y")
    assert (question["difficulty"], question["question_type"]) == ("hard", "long")


def test_topic_without_content_returns_empty_lists(
    client: TestClient, auth_headers: dict[str, str], seeded: SyllabusData, db_session: Session
) -> None:
    topic_id = _topic_id(db_session, 4, "Sequences")  # seeded with no formulas/questions
    for kind in ("formulas", "questions"):
        response = client.get(f"{API}/topics/{topic_id}/{kind}", headers=auth_headers)
        assert response.status_code == 200
        assert response.json() == []


@pytest.mark.parametrize("suffix", ["", "/formulas", "/questions"])
def test_missing_topic_is_404(
    client: TestClient, auth_headers: dict[str, str], suffix: str
) -> None:
    response = client.get(f"{API}/topics/999999{suffix}", headers=auth_headers)
    assert response.status_code == 404
    assert_error(response.json(), "not_found")


# ------------------------------------------------------------------ id validation


@pytest.mark.parametrize("bad_id", ["abc", "0", "-1", "2147483648", "1.5"])
@pytest.mark.parametrize("prefix", ["/units/", "/topics/"])
def test_invalid_ids_are_422(
    client: TestClient, auth_headers: dict[str, str], prefix: str, bad_id: str
) -> None:
    response = client.get(f"{API}{prefix}{bad_id}", headers=auth_headers)
    assert response.status_code == 422
    assert_error(response.json(), "validation_error")
