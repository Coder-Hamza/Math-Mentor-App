"""Practice: grade answers, award points, keep streaks and per-topic progress.

No Gemini call is made here (free quota is kept for the tutor): grading is SymPy + string
matching only, see ``answer_matching``.

Points
    easy 10, medium 20, hard 30, +5 when answered correctly in under 60 s, 0 when wrong.
    A question earns points only the FIRST time it is answered correctly. Since the answer
    is revealed after every submission, re-answering a question would otherwise farm points.
    Repeats still count towards accuracy and the streak.
"""

import logging
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from concurrent.futures import TimeoutError as FutureTimeoutError
from typing import Final

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import Settings, get_settings
from app.core.errors import AppError, NotFoundError
from app.models import Difficulty, PracticeQuestion, User
from app.repositories import PracticeQuestionRepository, ProgressRepository, UnitRepository
from app.schemas.practice import (
    PracticeQuestionPublic,
    PracticeSubmitRequest,
    PracticeSubmitResponse,
)
from app.services.practice.answer_matching import Evaluation, evaluate, evaluate_by_similarity

logger = logging.getLogger(__name__)

BASE_POINTS: Final = {Difficulty.EASY: 10, Difficulty.MEDIUM: 20, Difficulty.HARD: 30}
TIME_BONUS: Final = 5
TIME_BONUS_LIMIT_SECONDS: Final = 60
STREAK_CELEBRATION: Final = 3  # streak shown with a fire emoji, and "broken" when lost

# SymPy grading runs here so a pathological answer cannot hold the request past the timeout.
_grader = ThreadPoolExecutor(max_workers=4, thread_name_prefix="practice-grader")


class QuestionNotGradableError(AppError):
    status_code = 422
    code = "question_not_gradable"


# ------------------------------------------------------------------ pure rules


def evaluate_answer(question: PracticeQuestion, student_answer: str) -> Evaluation:
    """MCQ: exact (case-insensitive) match. Others: SymPy, then string similarity."""
    return evaluate(
        question.question_type, question.options, question.correct_answer, student_answer
    )


def calculate_points(difficulty: Difficulty, time_taken: int, is_correct: bool) -> int:
    if not is_correct:
        return 0
    bonus = TIME_BONUS if time_taken < TIME_BONUS_LIMIT_SECONDS else 0
    return BASE_POINTS[difficulty] + bonus


def get_encouragement(is_correct: bool, streak: int) -> str:
    """Urdu/English message.

    ``streak`` is the streak *including* this answer when it is correct, and the streak
    that was just broken when it is wrong.
    """
    if is_correct and streak >= STREAK_CELEBRATION:
        return f"Shabash! {streak} sawaal lagataar sahi! 🔥"
    if is_correct:
        return "Bilkul sahi! Bohat acha! ✅"
    if streak >= STREAK_CELEBRATION:
        return "Himmat mat haro! Agle mein zaroor sahi hoga 🌟"
    return "Koi baat nahi, dobara koshish karo 💪"


def _with_timeout(
    grade: Callable[[], Evaluation], fallback: Callable[[], Evaluation], timeout: float
) -> Evaluation:
    future = _grader.submit(grade)
    try:
        return future.result(timeout=timeout)
    except FutureTimeoutError:
        logger.warning("SymPy grading timed out after %.1fs; using text similarity", timeout)
        return fallback()


# ------------------------------------------------------------------ service


def to_public(question: PracticeQuestion) -> PracticeQuestionPublic:
    topic = question.topic
    return PracticeQuestionPublic(
        id=question.id,
        topic_id=topic.id,
        topic_title=topic.title,
        unit_id=topic.unit.id,
        unit_number=topic.unit.unit_number,
        unit_title=topic.unit.title,
        question_text=question.question_text,
        difficulty=question.difficulty,
        question_type=question.question_type,
        options=list(question.options) if question.options is not None else None,
    )


class PracticeService:
    def __init__(self, session: Session, settings: Settings | None = None) -> None:
        self._session = session
        self._settings = settings or get_settings()
        self._questions = PracticeQuestionRepository(session)
        self._progress = ProgressRepository(session)

    def random_questions(
        self, *, count: int, unit_id: int | None = None
    ) -> list[PracticeQuestionPublic]:
        if unit_id is not None and UnitRepository(self._session).get(unit_id) is None:
            raise NotFoundError(f"Unit {unit_id} not found")
        questions = self._questions.random_gradable(count=count, unit_id=unit_id)
        return [to_public(q) for q in questions]

    def grade(self, question: PracticeQuestion, student_answer: str) -> Evaluation:
        return _with_timeout(
            lambda: evaluate_answer(question, student_answer),
            lambda: evaluate_by_similarity(student_answer, question.correct_answer),
            self._settings.sympy_timeout_seconds,
        )

    def submit(self, user_id: int, request: PracticeSubmitRequest) -> PracticeSubmitResponse:
        # Serialize this student's submissions: streak, "first solve" and the progress row
        # are read-modify-write, so two parallel submits must not interleave.
        self._session.execute(select(User.id).where(User.id == user_id).with_for_update())

        question = self._questions.get_with_topic(request.question_id)
        if question is None:
            raise NotFoundError(f"Question {request.question_id} not found")
        if not question.is_gradable:
            raise QuestionNotGradableError(
                "This question cannot be checked automatically (proofs need a teacher)."
            )

        evaluation = self.grade(question, request.student_answer)
        previous_streak = self._progress.current_streak(user_id)
        already_solved = self._progress.has_solved(user_id, question.id)
        points = (
            0
            if already_solved
            else calculate_points(
                question.difficulty, request.time_taken_seconds, evaluation.is_correct
            )
        )
        self._progress.record_attempt(
            user_id,
            question.id,
            is_correct=evaluation.is_correct,
            points=points,
            time_taken_seconds=request.time_taken_seconds,
        )
        self._progress.update_after_attempt(
            user_id, question.topic_id, is_correct=evaluation.is_correct, points=points
        )
        streak = previous_streak + 1 if evaluation.is_correct else 0
        total_points = self._progress.total_points(user_id)
        self._session.commit()
        logger.info(
            "Practice answer graded: question=%d correct=%s method=%s",
            question.id,
            evaluation.is_correct,
            evaluation.method,
        )
        return PracticeSubmitResponse(
            is_correct=evaluation.is_correct,
            correct_answer=question.correct_answer,
            explanation=question.answer_explanation,
            points_earned=points,
            new_total_points=total_points,
            streak=streak,
            encouragement=get_encouragement(
                evaluation.is_correct, streak if evaluation.is_correct else previous_streak
            ),
            already_solved=already_solved,
        )
