import pytest
from alembic import command
from alembic.autogenerate import compare_metadata
from alembic.migration import MigrationContext
from alembic.script import ScriptDirectory
from sqlalchemy import Engine, inspect

from app.database.base import Base
from tests.integration.conftest import alembic_config

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
