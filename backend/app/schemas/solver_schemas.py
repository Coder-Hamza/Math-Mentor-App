"""Smart Question Solver: API contract and the Gemini output contract.

A student gives a chapter name, a question and (optionally) the book's answer; the AI solves
it step by step in the Pakistani textbook pattern. See ``services/tutor/solver_service.py``.
"""

from enum import StrEnum
from typing import Annotated

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, field_validator

from app.schemas.ai_schemas import Language, MathCheck
from app.schemas.common import StrictInputModel

MAX_CHAPTER_LENGTH = 200
MAX_SOLVER_QUESTION_LENGTH = 1000
MAX_BOOK_ANSWER_LENGTH = 500


class SolverDifficulty(StrEnum):
    EASY = "easy"
    MEDIUM = "medium"
    HARD = "hard"


# ------------------------------------------------------------------ API contract


class SolverRequest(StrictInputModel):
    chapter_name: Annotated[
        str,
        StringConstraints(strip_whitespace=True, min_length=1, max_length=MAX_CHAPTER_LENGTH),
    ]
    question: Annotated[
        str,
        StringConstraints(
            strip_whitespace=True, min_length=1, max_length=MAX_SOLVER_QUESTION_LENGTH
        ),
    ]
    book_answer: (
        Annotated[str, StringConstraints(strip_whitespace=True, max_length=MAX_BOOK_ANSWER_LENGTH)]
        | None
    ) = None
    grade_level: Annotated[
        str, StringConstraints(strip_whitespace=True, min_length=1, max_length=20)
    ] = "HSC-I"
    language: Language = Language.URDU_ENGLISH

    @field_validator("book_answer")
    @classmethod
    def _blank_is_none(cls, value: str | None) -> str | None:
        # The app sends "" when the optional field is left empty.
        return value or None


class SolverStep(BaseModel):
    step_number: int = Field(ge=1)
    title: str
    explanation: str
    formula_used: str | None = None
    calculation: str | None = None


class SolverResponse(BaseModel):
    question: str
    chapter: str
    solution: str = Field(description="The full solution in the textbook text pattern")
    steps: list[SolverStep]
    method_used: str
    formulas_applied: list[str]
    key_concepts: list[str]
    answer_verified: bool = Field(
        description="True only if a book answer was given and our answer matches it"
    )
    book_answer: str | None
    our_answer: str
    sympy_verified: bool
    difficulty_level: SolverDifficulty
    pro_tip: str
    warning: str | None = None


# ------------------------------------------------------------------ Gemini output contract


class GeminiSolverStep(BaseModel):
    model_config = ConfigDict(extra="ignore")

    title: str = Field(min_length=1, description="Short Roman-Urdu/English step title")
    explanation: str = Field(min_length=1)
    formula_used: str | None = None
    calculation: str | None = None


class GeminiSolverAnswer(BaseModel):
    """The JSON object Gemini is instructed to return for the solver."""

    model_config = ConfigDict(extra="ignore")

    restated_question: str = Field(min_length=1)
    given: list[str] = Field(default_factory=list)
    to_find: list[str] = Field(default_factory=list)
    steps: list[GeminiSolverStep] = Field(min_length=1)
    method_used: str = Field(min_length=1)
    formulas_applied: list[str] = Field(default_factory=list)
    key_concepts: list[str] = Field(default_factory=list)
    final_answer: str = Field(min_length=1)
    difficulty_level: SolverDifficulty = SolverDifficulty.MEDIUM
    exam_tip: str = Field(min_length=1)
    checks: list[MathCheck] = Field(default_factory=list)
