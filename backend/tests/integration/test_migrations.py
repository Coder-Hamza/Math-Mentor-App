import pytest
from alembic import command
from alembic.autogenerate import compare_metadata
from alembic.migration import MigrationContext
from alembic.script import ScriptDirectory
from sqlalchemy import Engine, inspect, text

from app.database.base import Base
from tests.conftest import alembic_config

pytestmark = pytest.mark.integration


def test_database_is_at_head(migrated_engine: Engine, test_database_url: str) -> None:
    head = ScriptDirectory.from_config(alembic_config(test_database_url)).get_current_head()
    with migrated_engine.connect() as connection:
        assert MigrationContext.configure(connection).get_current_revision() == head


def test_models_and_migrations_have_no_drift(migrated_engine: Engine) -> None:
    """Fails if someone changes a model without generating a migration."""
    with migrated_engine.connect() as connection:
        context = MigrationContext.configure(connection, opts={"compare_type": True})
        assert compare_metadata(context, Base.metadata) == []


def test_downgrade_then_upgrade_roundtrip(migrated_engine: Engine, test_database_url: str) -> None:
    config = alembic_config(test_database_url)
    command.downgrade(config, "base")
    assert set(inspect(migrated_engine).get_table_names()) <= {"alembic_version"}
    command.upgrade(config, "head")
    assert set(Base.metadata.tables) <= set(inspect(migrated_engine).get_table_names())


PHASE_4_REVISION = "f7794967963c"


def test_practice_answer_fields_exist(migrated_engine: Engine) -> None:
    inspector = inspect(migrated_engine)
    questions = {c["name"]: c for c in inspector.get_columns("practice_questions")}
    assert questions["correct_answer"]["nullable"] is False
    assert questions["answer_explanation"]["nullable"] is False
    assert questions["options"]["nullable"] is True
    assert questions["correct_answer"]["default"] is None  # backfill default was dropped
    progress = {c["name"] for c in inspector.get_columns("student_progress")}
    assert {"correct_count", "points"} <= progress
    attempts = {c["name"] for c in inspector.get_columns("practice_attempts")}
    assert {"user_id", "question_id", "is_correct", "points_earned", "time_taken_seconds"} <= (
        attempts
    )
    checks = {c["name"] for c in inspector.get_check_constraints("practice_questions")}
    assert "ck_practice_questions_mcq_has_options" in checks


def test_upgrade_backfills_existing_questions(
    migrated_engine: Engine, test_database_url: str
) -> None:
    """Rows created before this migration get an empty (ungradable) answer key."""
    config = alembic_config(test_database_url)
    command.downgrade(config, PHASE_4_REVISION)
    try:
        with migrated_engine.begin() as connection:
            unit_id = connection.execute(
                text(
                    "INSERT INTO units (unit_number, title, page_number) VALUES (99, 'U', 1) "
                    "RETURNING id"
                )
            ).scalar_one()
            topic_id = connection.execute(
                text(
                    "INSERT INTO topics (unit_id, title, difficulty_level) "
                    "VALUES (:u, 'T', 'easy') RETURNING id"
                ),
                {"u": unit_id},
            ).scalar_one()
            connection.execute(
                text(
                    "INSERT INTO practice_questions (topic_id, question_text, difficulty, "
                    "question_type) VALUES (:t, 'Old question', 'easy', 'short')"
                ),
                {"t": topic_id},
            )
        command.upgrade(config, "head")
        with migrated_engine.connect() as connection:
            row = connection.execute(
                text(
                    "SELECT correct_answer, answer_explanation, options FROM practice_questions "
                    "WHERE question_text = 'Old question'"
                )
            ).one()
        assert tuple(row) == ("", "", None)
    finally:
        command.upgrade(config, "head")
        with migrated_engine.begin() as connection:
            connection.execute(text("DELETE FROM units WHERE unit_number = 99"))
