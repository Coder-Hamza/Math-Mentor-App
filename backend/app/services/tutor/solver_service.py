"""Smart Question Solver: chapter + question (+ book answer) -> Gemini -> SymPy -> response.

* Gemini returns structured JSON; ``render_solution`` turns it into the textbook text pattern
  (Sawal / Diya hua / Poochha gaya / Hal / Qadam n / Jawab / Exam Tip).
* ``sympy_verified``: SymPy checks the claims Gemini lists (e.g. the answer substituted back
  into the equation), using the same rules as the tutor (``summarize``).
* ``answer_verified``: True only when the student gave the book's answer AND our answer is
  equivalent to it — by SymPy where both are mathematical (labels, ±, i, √, rounding are
  understood), otherwise by close text similarity.
* Time: Gemini gets ``solver - sympy`` seconds (40 s by default); SymPy work gets
  ``sympy_timeout_seconds``. The endpoint therefore finishes within ~45 s.

Privacy: the service never receives the user — only what the student typed, scrubbed of
contact details in ``GeminiService.solve_question``.
"""

import asyncio
import logging
from collections.abc import Sequence
from dataclasses import dataclass
from typing import Final

from app.core.config import Settings, get_settings
from app.schemas.ai_schemas import MathCheck, VerificationStatus
from app.schemas.solver_schemas import (
    GeminiSolverAnswer,
    SolverDifficulty,
    SolverRequest,
    SolverResponse,
    SolverStep,
)
from app.services.ai.errors import AITimeoutError
from app.services.ai.gemini_service import GeminiService
from app.services.ai.solver_prompts import render_solution
from app.services.mathematics.verifier import verify_identity
from app.services.practice.answer_matching import evaluate_text_answer
from app.services.tutor.tutor_service import MAX_CHECKS, VerificationSummary, summarize

logger = logging.getLogger(__name__)

WARNING_BOOK_MISMATCH: Final = (
    "Hamara jawab book ke jawab se match nahi karta. Book mein kabhi kabhi print ki "
    "ghalti hoti hai — apne teacher se zaroor confirm karein. "
    "(Our answer does not match the book's answer; please check with your teacher.)"
)
WARNING_SYMPY_FAILED: Final = (
    "Math engine ko is hal mein ghalti ka shak hai. Steps dhyan se check karein. "
    "(The math engine found a possible mistake; please check the steps carefully.)"
)
WARNING_UNSTRUCTURED: Final = (
    "AI ka jawab sahi format mein nahi aaya, is liye seedha text dikhaya gaya hai aur "
    "check nahi ho saka. Dobara solve kar ke dekhein. "
    "(The answer was not in the expected format, so it is shown as plain text.)"
)
WARNING_CHECK_TIMEOUT: Final = (
    "Math engine ko check karne mein bohat der lagi, is liye jawab verify nahi hua. "
    "(Checking took too long, so the answer is not verified.)"
)

UNSTRUCTURED_TIP: Final = (
    "Board exam mein har step likhein aur formula ka naam zaroor batayein — "
    "steps ke bhi marks milte hain."
)


@dataclass(frozen=True)
class _Checks:
    sympy: VerificationSummary
    book_match: bool
    timed_out: bool = False


def _verify_claims(checks: Sequence[MathCheck]) -> VerificationSummary:
    return summarize([verify_identity(c.lhs, c.rhs) for c in checks])


def answers_match(our_answer: str, book_answer: str) -> bool:
    """Is our final answer the same as the book's? SymPy first, text similarity otherwise."""
    return evaluate_text_answer(correct_answer=book_answer, student_answer=our_answer).is_correct


def _run_checks(answer: GeminiSolverAnswer, book_answer: str | None) -> _Checks:
    sympy = _verify_claims(answer.checks[:MAX_CHECKS])
    match = bool(book_answer) and answers_match(answer.final_answer, book_answer or "")
    return _Checks(sympy=sympy, book_match=match)


def _warning(checks: _Checks, book_answer: str | None) -> str | None:
    parts: list[str] = []
    if book_answer and not checks.book_match:
        parts.append(WARNING_BOOK_MISMATCH)
    if checks.timed_out:
        parts.append(WARNING_CHECK_TIMEOUT)
    elif checks.sympy.status is VerificationStatus.FAILED:
        parts.append(WARNING_SYMPY_FAILED)
    return " ".join(parts) or None


class SolverService:
    def __init__(self, gemini: GeminiService, settings: Settings | None = None) -> None:
        self._gemini = gemini
        self._settings = settings or get_settings()

    async def solve_question(self, request: SolverRequest) -> SolverResponse:
        try:
            async with asyncio.timeout(self._settings.solver_gemini_budget_seconds):
                result = await self._gemini.solve_question(
                    chapter=request.chapter_name,
                    question=request.question,
                    book_answer=request.book_answer,
                    grade_level=request.grade_level,
                    language=request.language,
                )
        except TimeoutError:
            raise AITimeoutError() from None

        if result.answer is None:
            logger.info("Solver answer unstructured (model=%s)", result.model)
            return self._unstructured(request, result.raw_text)

        answer = result.answer
        logger.info(
            "Solver answer received: model=%s steps=%d checks=%d book_answer=%s",
            result.model,
            len(answer.steps),
            len(answer.checks),
            request.book_answer is not None,
        )
        checks = await self._check(answer, request.book_answer)
        return SolverResponse(
            question=request.question,
            chapter=request.chapter_name,
            solution=render_solution(answer),
            steps=[
                SolverStep(
                    step_number=number,
                    title=step.title,
                    explanation=step.explanation,
                    formula_used=step.formula_used or None,
                    calculation=step.calculation or None,
                )
                for number, step in enumerate(answer.steps, start=1)
            ],
            method_used=answer.method_used,
            formulas_applied=answer.formulas_applied,
            key_concepts=answer.key_concepts,
            answer_verified=checks.book_match,
            book_answer=request.book_answer,
            our_answer=answer.final_answer,
            sympy_verified=checks.sympy.verified,
            difficulty_level=answer.difficulty_level,
            pro_tip=answer.exam_tip,
            warning=_warning(checks, request.book_answer),
        )

    async def _check(self, answer: GeminiSolverAnswer, book_answer: str | None) -> _Checks:
        try:
            async with asyncio.timeout(self._settings.sympy_timeout_seconds):
                checks = await asyncio.to_thread(_run_checks, answer, book_answer)
        except TimeoutError:
            logger.warning("Solver verification timed out")
            return _Checks(sympy=summarize([]), book_match=False, timed_out=True)
        if checks.sympy.status is VerificationStatus.FAILED:
            logger.info("SymPy rejected a solver claim")
        return checks

    @staticmethod
    def _unstructured(request: SolverRequest, raw_text: str) -> SolverResponse:
        """Gemini ignored the JSON format: still show its text, clearly unverified."""
        return SolverResponse(
            question=request.question,
            chapter=request.chapter_name,
            solution=raw_text,
            steps=[],
            method_used="",
            formulas_applied=[],
            key_concepts=[],
            answer_verified=False,
            book_answer=request.book_answer,
            our_answer="",
            sympy_verified=False,
            difficulty_level=SolverDifficulty.MEDIUM,
            pro_tip=UNSTRUCTURED_TIP,
            warning=WARNING_UNSTRUCTURED,
        )
