import pytest
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.database.seed import SyllabusData, load_syllabus, main, seed_database
from app.models import Formula, PracticeQuestion, Topic, Unit
from app.repositories import TopicRepository, UnitRepository

pytestmark = pytest.mark.integration

DATA = load_syllabus()


def _count(session: Session, model: type) -> int:
    return session.scalar(select(func.count()).select_from(model)) or 0


def test_seed_inserts_full_syllabus(db_session: Session) -> None:
    report = seed_database(db_session, DATA)

    assert report.created["units"] == _count(db_session, Unit) == 12
    assert report.created["topics"] == _count(db_session, Topic) == len(DATA.topics)
    assert report.created["formulas"] == _count(db_session, Formula) == len(DATA.formulas)
    assert (
        report.created["practice_questions"]
        == _count(db_session, PracticeQuestion)
        == len(DATA.questions)
    )


def test_seeded_units_are_correct(db_session: Session) -> None:
    seed_database(db_session, DATA)
    units = UnitRepository(db_session).list_with_topics()
    assert [u.unit_number for u in units] == list(range(1, 13))
    vectors = units[2]
    assert (vectors.title, vectors.page_number) == ("Vectors", 74)
    assert "Scalar (Dot) Product" in [t.title for t in vectors.topics]


def test_seed_is_idempotent(db_session: Session) -> None:
    seed_database(db_session, DATA)
    second = seed_database(db_session, DATA)
    assert sum(second.created.values()) == 0
    assert sum(second.updated.values()) == 0
    assert _count(db_session, Unit) == 12


def test_seed_updates_changed_rows(db_session: Session) -> None:
    seed_database(db_session, DATA)
    edited_units = [
        u.model_copy(update={"description": "Edited"}) if u.unit_number == 1 else u
        for u in DATA.units
    ]
    edited = SyllabusData(
        units=edited_units, topics=DATA.topics, formulas=DATA.formulas, questions=DATA.questions
    )

    report = seed_database(db_session, edited)

    assert report.updated["units"] == 1
    assert sum(report.created.values()) == 0
    unit = UnitRepository(db_session).get_by_number(1)
    assert unit is not None
    assert unit.description == "Edited"


def test_seeded_formulas_attach_to_correct_topic(db_session: Session) -> None:
    seed_database(db_session, DATA)
    unit = UnitRepository(db_session).get_by_number(10)
    assert unit is not None
    topic = TopicRepository(db_session).get_by_title(unit.id, "Fundamental Law of Trigonometry")
    assert topic is not None
    loaded = TopicRepository(db_session).get_with_content(topic.id)
    assert loaded is not None
    assert [f.expression for f in loaded.formulas] == ["cos(x - y) = cos(x)*cos(y) + sin(x)*sin(y)"]


def test_main_seeds_and_commits(db_session: Session, capsys: pytest.CaptureFixture[str]) -> None:
    report = main(session_factory=lambda: db_session)
    assert report.created["units"] == 12
    assert "Seed complete" in capsys.readouterr().out
    assert _count(db_session, Unit) == 12  # committed to the (outer, rolled-back) transaction
