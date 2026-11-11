"""Seed the database from the version-controlled syllabus JSON in ``/syllabus``.

Idempotent: rows are matched on natural keys and inserted or updated, so the script can be
re-run after editing the JSON. Rows removed from the JSON are *not* deleted (student progress
may reference them).

Usage (from ``backend/``)::

    uv run python -m app.database.seed
"""

import json
from collections import Counter
from collections.abc import Callable
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Self

from pydantic import BaseModel, ConfigDict, Field, model_validator
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import SYLLABUS_DIR
from app.database.base import Base
from app.database.session import get_sessionmaker
from app.models import Formula, PracticeQuestion, Topic, Unit
from app.models.enums import Difficulty, QuestionType

UNITS_FILE = Path("chapters/units.json")
TOPICS_FILE = Path("topics/topics.json")
FORMULAS_FILE = Path("formulas/formulas.json")
QUESTIONS_FILE = Path("question_patterns/practice_questions.json")


class _SeedModel(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, str_strip_whitespace=True)


class UnitSeed(_SeedModel):
    unit_number: int = Field(gt=0)
    title: str = Field(min_length=1, max_length=150)
    page_number: int = Field(gt=0)
    description: str | None = None


class TopicSeed(_SeedModel):
    unit_number: int
    title: str = Field(min_length=1, max_length=200)
    difficulty_level: Difficulty
    description: str | None = None


class FormulaSeed(_SeedModel):
    unit_number: int
    topic: str
    name: str = Field(min_length=1, max_length=200)
    expression: str = Field(min_length=1)
    identity: bool = False  # True => verified symbolically/numerically by the test-suite
    description: str | None = None


class QuestionSeed(_SeedModel):
    unit_number: int
    topic: str
    question_text: str = Field(min_length=1)
    difficulty: Difficulty
    question_type: QuestionType


def _duplicates[T](keys: list[T]) -> list[T]:
    return [key for key, count in Counter(keys).items() if count > 1]


class SyllabusData(_SeedModel):
    units: list[UnitSeed]
    topics: list[TopicSeed]
    formulas: list[FormulaSeed]
    questions: list[QuestionSeed]

    @model_validator(mode="after")
    def _check_integrity(self) -> Self:
        errors: list[str] = []
        unit_numbers = [u.unit_number for u in self.units]
        topic_keys = [(t.unit_number, t.title) for t in self.topics]
        checks: list[tuple[str, list[Any]]] = [
            ("unit_number", unit_numbers),
            ("topic", topic_keys),
            ("formula", [(f.unit_number, f.topic, f.name) for f in self.formulas]),
            ("question", [(q.unit_number, q.topic, q.question_text) for q in self.questions]),
        ]
        for label, keys in checks:
            if dupes := _duplicates(keys):
                errors.append(f"duplicate {label}: {dupes}")

        known_units, known_topics = set(unit_numbers), set(topic_keys)
        errors += [
            f"topic {t.title!r} references unknown unit {t.unit_number}"
            for t in self.topics
            if t.unit_number not in known_units
        ]
        errors += [
            f"unit {n} has no topics"
            for n in unit_numbers
            if n not in {t.unit_number for t in self.topics}
        ]
        for kind, items in (("formula", self.formulas), ("question", self.questions)):
            errors += [
                f"{kind} references unknown topic ({item.unit_number}, {item.topic!r})"
                for item in items
                if (item.unit_number, item.topic) not in known_topics
            ]
        if errors:
            raise ValueError("invalid syllabus data:\n  " + "\n  ".join(errors))
        return self


def load_syllabus(directory: Path = SYLLABUS_DIR) -> SyllabusData:
    """Read and validate all syllabus JSON files under ``directory``."""

    def read(relative: Path) -> Any:
        return json.loads((directory / relative).read_text(encoding="utf-8"))

    return SyllabusData(
        units=read(UNITS_FILE),
        topics=read(TOPICS_FILE),
        formulas=read(FORMULAS_FILE),
        questions=read(QUESTIONS_FILE),
    )


@dataclass
class SeedReport:
    created: Counter[str] = field(default_factory=Counter)
    updated: Counter[str] = field(default_factory=Counter)

    def summary(self) -> str:
        tables = ("units", "topics", "formulas", "practice_questions")
        return ", ".join(
            f"{t}: +{self.created[t]} created / {self.updated[t]} updated" for t in tables
        )


def _upsert[K, M: Base](
    session: Session,
    existing: dict[K, M],
    key: K,
    model: type[M],
    values: dict[str, Any],
    report: SeedReport,
) -> M:
    table = model.__tablename__
    obj = existing.get(key)
    if obj is None:
        obj = model(**values)
        session.add(obj)
        existing[key] = obj
        report.created[table] += 1
        return obj
    changed = False
    for name, value in values.items():
        if getattr(obj, name) != value:
            setattr(obj, name, value)
            changed = True
    if changed:
        report.updated[table] += 1
    return obj


def seed_database(session: Session, data: SyllabusData) -> SeedReport:
    """Upsert all syllabus rows. Flushes, but the caller commits."""
    report = SeedReport()

    units = {u.unit_number: u for u in session.scalars(select(Unit))}
    for u in data.units:
        _upsert(session, units, u.unit_number, Unit, u.model_dump(), report)
    session.flush()

    topics = {(t.unit_id, t.title): t for t in session.scalars(select(Topic))}
    for t in data.topics:
        unit_id = units[t.unit_number].id
        values = t.model_dump(exclude={"unit_number"}) | {"unit_id": unit_id}
        _upsert(session, topics, (unit_id, t.title), Topic, values, report)
    session.flush()

    def topic_id(unit_number: int, title: str) -> int:
        return topics[(units[unit_number].id, title)].id

    formulas = {(f.topic_id, f.name): f for f in session.scalars(select(Formula))}
    for f in data.formulas:
        tid = topic_id(f.unit_number, f.topic)
        values = f.model_dump(include={"name", "expression", "description"}) | {"topic_id": tid}
        _upsert(session, formulas, (tid, f.name), Formula, values, report)

    questions = {
        (q.topic_id, q.question_text): q for q in session.scalars(select(PracticeQuestion))
    }
    for q in data.questions:
        tid = topic_id(q.unit_number, q.topic)
        values = q.model_dump(exclude={"unit_number", "topic"}) | {"topic_id": tid}
        _upsert(session, questions, (tid, q.question_text), PracticeQuestion, values, report)

    session.flush()
    return report


def main(session_factory: Callable[[], Session] | None = None) -> SeedReport:
    data = load_syllabus()
    factory = session_factory or get_sessionmaker()
    with factory() as session:
        report = seed_database(session, data)
        session.commit()
    print(f"Seed complete — {report.summary()}")
    return report


if __name__ == "__main__":
    main()
