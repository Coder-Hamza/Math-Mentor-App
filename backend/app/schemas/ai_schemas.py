"""Schemas for the AI tutor: API contract (request/response) and the Gemini output contract."""

from enum import StrEnum
from typing import Annotated

from pydantic import BaseModel, ConfigDict, Field, StringConstraints

from app.schemas.common import StrictInputModel

MAX_QUESTION_LENGTH = 500


class Language(StrEnum):
    URDU_ENGLISH = "urdu_english"
    ENGLISH = "english"


class VerificationStatus(StrEnum):
    VERIFIED = "verified"  # every checkable claim held at all sample points
    FAILED = "failed"  # at least one claim is mathematically wrong
    UNVERIFIABLE = "unverifiable"  # nothing could be checked (not the same as wrong)


# ------------------------------------------------------------------ API contract


class TutorRequest(StrictInputModel):
    question: Annotated[
        str,
        StringConstraints(strip_whitespace=True, min_length=1, max_length=MAX_QUESTION_LENGTH),
    ]
    topic_id: Annotated[int, Field(ge=1, le=2_147_483_647)]
    language: Language = Language.URDU_ENGLISH


class TutorResponse(BaseModel):
    question: str
    explanation: str
    steps: list[str]
    formulas_used: list[str]
    sympy_verified: bool
    verification_confidence: float = Field(ge=0, le=1)
    verification_status: VerificationStatus
    topic: str
    unit: str
    warning: str | None = None


# ------------------------------------------------------------------ Gemini output contract


class MathCheck(BaseModel):
    """A claim SymPy can test: ``lhs`` must equal ``rhs`` for all values of the variables."""

    model_config = ConfigDict(extra="ignore")

    lhs: str = Field(description="Left side in SymPy syntax, e.g. 'sin(2*x)'")
    rhs: str = Field(description="Right side in SymPy syntax, e.g. '2*sin(x)*cos(x)'")


class GeminiTutorAnswer(BaseModel):
    """The JSON object Gemini is instructed to return."""

    model_config = ConfigDict(extra="ignore")

    explanation: str = Field(min_length=1)
    steps: list[str] = Field(default_factory=list)
    formulas_used: list[str] = Field(default_factory=list)
    checks: list[MathCheck] = Field(default_factory=list)
