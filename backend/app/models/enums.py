"""Enumerations shared by models and schemas."""

from enum import StrEnum

from sqlalchemy import Enum


class Difficulty(StrEnum):
    EASY = "easy"
    MEDIUM = "medium"
    HARD = "hard"


class QuestionType(StrEnum):
    MCQ = "mcq"
    SHORT = "short"
    LONG = "long"
    PROOF = "proof"


def str_enum_column[E: StrEnum](enum_cls: type[E], name: str) -> Enum:
    """Store a StrEnum as VARCHAR + CHECK constraint (portable, migration-friendly)."""
    return Enum(
        enum_cls,
        name=name,
        native_enum=False,
        create_constraint=True,
        length=16,
        validate_strings=True,
        values_callable=lambda members: [member.value for member in members],
    )
