"""Pure practice rules: evaluate_answer, calculate_points, get_encouragement, grading timeout."""

import threading

import pytest

from app.models import Difficulty, PracticeQuestion, QuestionType
from app.services.practice import practice_service as ps
from app.services.practice.answer_matching import Evaluation
from app.services.practice.practice_service import (
    calculate_points,
    evaluate_answer,
    get_encouragement,
)


def _question(
    question_type: QuestionType, answer: str, options: list[str] | None = None
) -> PracticeQuestion:
    return PracticeQuestion(
        question_type=question_type,
        options=options,
        correct_answer=answer,
        answer_explanation="E",
        difficulty=Difficulty.EASY,
    )


# ------------------------------------------------------------------ evaluate_answer


def test_evaluate_answer_mcq_is_case_insensitive_exact_match() -> None:
    q = _question(QuestionType.MCQ, "Domain: x >= 2", ["Domain: x >= 2", "b", "c", "d"])
    assert evaluate_answer(q, "domain: X >= 2").is_correct
    assert evaluate_answer(q, "A").is_correct
    assert not evaluate_answer(q, "Domain: x > 2").is_correct


def test_evaluate_answer_short_uses_sympy_first() -> None:
    result = evaluate_answer(_question(QuestionType.SHORT, "3/2"), "1.5")
    assert (result.is_correct, result.method, result.confidence) == (True, "sympy", 1.0)


def test_evaluate_answer_long_falls_back_to_similarity() -> None:
    q = _question(QuestionType.LONG, "a parabola opening upwards")
    result = evaluate_answer(q, "A parabola, opening upwards")
    assert (result.is_correct, result.method) == (True, "similarity")


# ------------------------------------------------------------------ calculate_points


@pytest.mark.parametrize(
    ("difficulty", "time_taken", "is_correct", "points"),
    [
        (Difficulty.EASY, 120, True, 10),
        (Difficulty.MEDIUM, 120, True, 20),
        (Difficulty.HARD, 120, True, 30),
        (Difficulty.EASY, 59, True, 15),
        (Difficulty.MEDIUM, 0, True, 25),
        (Difficulty.HARD, 30, True, 35),
        (Difficulty.HARD, 60, True, 30),  # bonus is for UNDER 60 s
        (Difficulty.EASY, 10, False, 0),
        (Difficulty.HARD, 500, False, 0),
    ],
)
def test_calculate_points(
    difficulty: Difficulty, time_taken: int, is_correct: bool, points: int
) -> None:
    assert calculate_points(difficulty, time_taken, is_correct) == points


# ------------------------------------------------------------------ get_encouragement


@pytest.mark.parametrize(
    ("is_correct", "streak", "message"),
    [
        (True, 1, "Bilkul sahi! Bohat acha! ✅"),
        (True, 2, "Bilkul sahi! Bohat acha! ✅"),
        (True, 3, "Shabash! 3 sawaal lagataar sahi! 🔥"),
        (True, 10, "Shabash! 10 sawaal lagataar sahi! 🔥"),
        (False, 0, "Koi baat nahi, dobara koshish karo 💪"),
        (False, 2, "Koi baat nahi, dobara koshish karo 💪"),
        (False, 3, "Himmat mat haro! Agle mein zaroor sahi hoga 🌟"),
        (False, 7, "Himmat mat haro! Agle mein zaroor sahi hoga 🌟"),
    ],
)
def test_get_encouragement(is_correct: bool, streak: int, message: str) -> None:
    assert get_encouragement(is_correct, streak) == message


# ------------------------------------------------------------------ timeout


def test_grading_timeout_falls_back() -> None:
    release = threading.Event()

    def slow() -> Evaluation:
        release.wait(5)
        return Evaluation(is_correct=True, confidence=1.0, method="sympy")

    fallback = Evaluation(is_correct=False, confidence=0.5, method="similarity")
    try:
        assert ps._with_timeout(slow, lambda: fallback, 0.05) is fallback
    finally:
        release.set()


def test_grading_within_timeout_returns_result() -> None:
    fast = Evaluation(is_correct=True, confidence=1.0, method="sympy")
    assert ps._with_timeout(lambda: fast, lambda: pytest.fail("no fallback"), 5) is fast
