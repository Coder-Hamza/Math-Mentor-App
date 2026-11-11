"""Tutor orchestration: question -> syllabus context -> Gemini -> SymPy -> TutorResponse.

Accuracy rules:
* A claim SymPy proves wrong is never reported as verified; the student sees a warning.
* "Could not verify" is a warning, not an error — the student still gets the answer.
* Gemini gets ``tutor - sympy`` seconds; SymPy gets ``sympy_timeout_seconds``. The endpoint
  therefore always finishes within ``tutor_timeout_seconds`` (+ a few ms of DB work).

Privacy: this service never receives the user — only the question and topic id.
"""

import asyncio
import logging
from collections.abc import Sequence
from dataclasses import dataclass
from typing import Final

from sqlalchemy.orm import Session

from app.core.config import Settings, get_settings
from app.core.errors import NotFoundError
from app.repositories import TopicRepository
from app.schemas.ai_schemas import (
    MathCheck,
    TutorRequest,
    TutorResponse,
    VerificationStatus,
)
from app.services.ai.errors import AITimeoutError
from app.services.ai.gemini_service import GeminiService, describe_answer
from app.services.mathematics.verifier import VerificationResult, verify_identity

logger = logging.getLogger(__name__)

MAX_CHECKS: Final = 10

WARNING_UNVERIFIABLE: Final = (
    "This answer could not be checked automatically by the math engine. "
    "Please review the steps carefully."
)
WARNING_PARTIAL: Final = (
    "Some steps could not be checked automatically by the math engine; "
    "the steps that were checked are correct."
)
WARNING_FAILED: Final = (
    "The math engine found a possible mistake in this answer. "
    "Please double-check the steps with your teacher or textbook."
)
WARNING_UNSTRUCTURED: Final = (
    "The tutor's answer was not in the expected format, so it is shown as plain text "
    "and could not be checked by the math engine."
)
WARNING_VERIFY_TIMEOUT: Final = (
    "The math engine took too long to check this answer, so it is not verified. "
    "Please review the steps carefully."
)


@dataclass(frozen=True)
class TopicContext:
    topic: str
    unit: str  # e.g. "Unit 10: Trigonometric Identities ..."
    unit_title: str
    formulas: tuple[str, ...]


@dataclass(frozen=True)
class VerificationSummary:
    status: VerificationStatus
    verified: bool
    confidence: float
    warning: str | None


def summarize(results: Sequence[VerificationResult]) -> VerificationSummary:
    """Combine per-claim results. Confidence = share of all claims that were verified."""
    if not results:
        return VerificationSummary(
            VerificationStatus.UNVERIFIABLE, False, 0.0, WARNING_UNVERIFIABLE
        )
    verified = sum(r.status is VerificationStatus.VERIFIED for r in results)
    failed = sum(r.status is VerificationStatus.FAILED for r in results)
    confidence = round(verified / len(results), 4)
    if failed:
        return VerificationSummary(VerificationStatus.FAILED, False, confidence, WARNING_FAILED)
    if not verified:
        return VerificationSummary(
            VerificationStatus.UNVERIFIABLE, False, 0.0, WARNING_UNVERIFIABLE
        )
    warning = None if verified == len(results) else WARNING_PARTIAL
    return VerificationSummary(VerificationStatus.VERIFIED, True, confidence, warning)


def _verify_all(checks: Sequence[MathCheck]) -> list[VerificationResult]:
    return [verify_identity(check.lhs, check.rhs) for check in checks]


class TutorService:
    def __init__(
        self, session: Session, gemini: GeminiService, settings: Settings | None = None
    ) -> None:
        self._session = session
        self._gemini = gemini
        self._settings = settings or get_settings()

    def load_context(self, topic_id: int) -> TopicContext:
        topic = TopicRepository(self._session).get_with_content(topic_id)
        if topic is None:
            raise NotFoundError(f"Topic {topic_id} not found")
        unit = topic.unit
        return TopicContext(
            topic=topic.title,
            unit=f"Unit {unit.unit_number}: {unit.title}",
            unit_title=unit.title,
            formulas=tuple(f"{f.name}: {f.expression}" for f in topic.formulas),
        )

    async def ask(self, request: TutorRequest) -> TutorResponse:
        context = await asyncio.to_thread(self.load_context, request.topic_id)
        try:
            async with asyncio.timeout(self._settings.gemini_budget_seconds):
                result = await self._gemini.ask_tutor(
                    question=request.question,
                    topic=context.topic,
                    unit=context.unit,
                    language=request.language,
                    reference_formulas=context.formulas,
                )
        except TimeoutError:
            raise AITimeoutError() from None
        logger.info("Tutor answer received: %s", describe_answer(result))

        if result.structured:
            summary = await self._verify(result.answer.checks[:MAX_CHECKS])
        else:
            summary = VerificationSummary(
                VerificationStatus.UNVERIFIABLE, False, 0.0, WARNING_UNSTRUCTURED
            )

        answer = result.answer
        return TutorResponse(
            question=request.question,
            explanation=answer.explanation,
            steps=answer.steps,
            formulas_used=answer.formulas_used,
            sympy_verified=summary.verified,
            verification_confidence=summary.confidence,
            verification_status=summary.status,
            topic=context.topic,
            unit=context.unit_title,
            warning=summary.warning,
        )

    async def _verify(self, checks: Sequence[MathCheck]) -> VerificationSummary:
        if not checks:
            return summarize([])
        try:
            async with asyncio.timeout(self._settings.sympy_timeout_seconds):
                results = await asyncio.to_thread(_verify_all, checks)
        except TimeoutError:
            logger.warning("SymPy verification timed out for %d checks", len(checks))
            return VerificationSummary(
                VerificationStatus.UNVERIFIABLE, False, 0.0, WARNING_VERIFY_TIMEOUT
            )
        for check, outcome in zip(checks, results, strict=True):
            if outcome.status is VerificationStatus.FAILED:
                logger.info("SymPy rejected a tutor claim: %s", outcome.error_message)
            elif outcome.status is VerificationStatus.UNVERIFIABLE:
                logger.debug("Unverifiable claim (%s): %r", outcome.error_message, check.lhs)
        return summarize(results)
