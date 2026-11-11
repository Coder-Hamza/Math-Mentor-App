"""Answer grading without AI: MCQ matching, SymPy comparison, string-similarity fallback."""

import pytest

from app.models import QuestionType
from app.services.practice import answer_matching as am
from app.services.practice.answer_matching import (
    NotMathematicalError,
    compare_math,
    evaluate,
    evaluate_by_similarity,
    evaluate_mcq,
    evaluate_text_answer,
    normalize_text,
    parse_parts,
)

MINUS = chr(0x2212)
SQRT = chr(0x221A)
PI = chr(0x03C0)
DEG = chr(0x00B0)
PLUS_MINUS = chr(0x00B1)
APPROX = chr(0x2248)

OPTIONS = ["1 + i", f"{MINUS}1 {MINUS} i", f"{MINUS}1 + i", f"1 {MINUS} i"]
CORRECT_OPTION = f"{MINUS}1 {MINUS} i"


# ------------------------------------------------------------------ MCQ


@pytest.mark.parametrize(
    "answer",
    [CORRECT_OPTION, "-1 - i", "-1-i", "  -1  -  I ", "B", "b", "b)", "(b)", "B.", "option b"],
)
def test_mcq_accepts_option_text_or_letter(answer: str) -> None:
    result = evaluate_mcq(OPTIONS, CORRECT_OPTION, answer)
    assert result == am.Evaluation(is_correct=True, confidence=1.0, method="mcq")


@pytest.mark.parametrize("answer", ["A", "c", "1 + i", "-1 + i", "e", "-1 - i - 0", "minus one"])
def test_mcq_rejects_other_choices(answer: str) -> None:
    assert evaluate_mcq(OPTIONS, CORRECT_OPTION, answer).is_correct is False


def test_mcq_letter_without_four_options_is_plain_text() -> None:
    assert evaluate_mcq(["x", "y"], "b", "B").is_correct is True  # compared as text
    assert evaluate_mcq(["x", "y"], "y", "B").is_correct is False


def test_mcq_is_exact_not_mathematical() -> None:
    # Spec: MCQ uses exact (case-insensitive) matching, never SymPy.
    assert evaluate_mcq(["5", "11", "-5", "8"], "5", "10/2").is_correct is False


# ------------------------------------------------------------------ maths (SymPy)

CASES: list[tuple[str, list[str], list[str]]] = [
    (f"{MINUS}1 + 2i", ["-1+2i", "2i-1", "-1 + 2 i", "-1 + 2*I"], ["2i+1", "-1-2i"]),
    (
        f"2 + 3i, 2 {MINUS} 3i",
        ["2+3i, 2-3i", "2-3i and 2+3i", f"2{PLUS_MINUS}3i", "2 - 3i; 2 + 3i"],
        ["2+3i", "2+3i, 2-3i, 1", "2+3i, 2+3i"],
    ),
    (
        "x = 1, y = 2, z = 3",
        ["x=1,y=2,z=3", "z=3, y=2, x=1", "1,2,3", "1, 2 and 3"],
        ["3,2,1", "x=1, y=2, w=3", "x=1, y=3, z=2"],
    ),
    (
        f"60{DEG}",
        ["60", f"60{DEG}", "pi/3", f"{PI}/3", "60 degrees", "60 deg", "1.047", "1.05"],
        ["30", "1.04", "1.1", "pi/6"],
    ),
    (f"2{SQRT}6", ["2sqrt(6)", f"2{SQRT}(6)", "4.899", "4.90", "sqrt(24)"], ["4.8", "4.9", "5"]),
    ("3/2", ["1.5", "3/2", "1.50", "6/4"], ["2/3", "1.4"]),
    ("n/(n + 1)", ["n/(n+1)", "1-1/(n+1)", "the answer is n/(n+1)"], ["n/(n-1)", "1/(n+1)"]),
    ("11/36", ["11/36", "0.3056", "0.31"], ["0.3", "1/3", "0.32"]),
    ("9.950", ["9.95", "9.950", "sqrt(99)", f"{SQRT}99"], ["9.94", "9.9", "10"]),
    ("x = 1, x = 3", ["1, 3", "3 and 1", "x=1 or x=3", "x = 3, x = 1"], ["x=1", "1,2"]),
    ("Z = 12", ["12", "Z=12", "Zmax = 12", "Ans: 12", "jawab 12"], ["11", "Z = 13"]),
    (
        f"50{SQRT}3/3 m",
        [
            "28.87",
            "28.87 m",
            "28.87m",
            "50/sqrt(3)",
            f"50/{SQRT}3 {APPROX} 28.87 m",
            "28.87 metres",
        ],
        ["28.9", "29", "28.80"],
    ),
    (
        "R = 65/8, r = 4",
        ["R=65/8, r=4", "r = 4, R = 8.125", "8.125, 4"],
        ["4, 8.125", "R=4, r=65/8", "R=65/8"],
    ),
    (
        f"{MINUS}{PI}/6",
        ["-pi/6", f"-30{DEG}", "-30", "-0.5236", f"-{PI}/6", "-0.52"],
        ["pi/6", "30", "-0.5"],
    ),
    ("2870", ["2870", "2,870", "2870."], ["2860", "287"]),
    ("120", ["120", "1.2e2"], ["121"]),
]


@pytest.mark.parametrize(
    ("expected", "answer"),
    [(e, a) for e, right, _ in CASES for a in right],
)
def test_equivalent_answers_are_correct(expected: str, answer: str) -> None:
    result = evaluate_text_answer(expected, answer)
    assert result.is_correct, f"{answer!r} should match {expected!r}"
    assert (result.method, result.confidence) == ("sympy", 1.0)


@pytest.mark.parametrize(
    ("expected", "answer"),
    [(e, a) for e, _, wrong in CASES for a in wrong],
)
def test_wrong_answers_are_rejected(expected: str, answer: str) -> None:
    result = evaluate_text_answer(expected, answer)
    assert not result.is_correct, f"{answer!r} should NOT match {expected!r}"


def test_rounding_needs_two_decimals() -> None:
    # 9.9 is a correct 1-decimal rounding of sqrt(99), but too coarse to count.
    assert compare_math("9.9", "sqrt(99)") is False
    assert compare_math("9.95", "sqrt(99)") is True


def test_symbolic_answers_compare_as_identities() -> None:
    assert compare_math("(x+1)^2", "x^2 + 2x + 1") is True
    assert compare_math("(x+1)^2", "x^2 + 1") is False


@pytest.mark.parametrize(
    "answer",
    [
        "the half-plane below the line",
        "[[2, -1], [-5, 3]]",
        "__import__('os')",
        "x" * 400,
        "1, , 2",
        "",
    ],
)
def test_non_mathematical_answers_raise(answer: str) -> None:
    with pytest.raises(NotMathematicalError):
        parse_parts(answer)


def test_unverifiable_identity_is_not_mathematical() -> None:
    # 1/(x - x) has no value anywhere, so it cannot be compared.
    with pytest.raises(NotMathematicalError):
        compare_math("1/(x - x)", "x")


def test_constant_without_value_is_not_mathematical() -> None:
    with pytest.raises(NotMathematicalError):
        compare_math("1/0", "1")


def test_parse_parts_details() -> None:
    parts = parse_parts(f"R = 65/8, r = 4.25, {PI}")
    assert [p.label for p in parts] == ["R", "r", None]
    assert parts[1].tolerance == pytest.approx(0.005)
    assert parts[0].tolerance == 0.0
    assert [p.angle for p in parts] == [False, False, True]


def test_normalize_text() -> None:
    assert normalize_text(f"  {MINUS}1  {MINUS} I. ") == "-1 - i"


# ------------------------------------------------------------------ similarity fallback


def test_text_answers_fall_back_to_similarity() -> None:
    expected = "The half-plane on and below the line"
    close = evaluate_text_answer(expected, "the half plane on and below the line")
    assert close.is_correct
    assert close.method == "similarity"
    far = evaluate_text_answer(expected, "above the line")
    assert not far.is_correct
    assert far.method == "similarity"
    assert 0 < far.confidence <= 1


def test_similarity_confidence() -> None:
    exact = evaluate_by_similarity("Domain x >= 2", "domain x >= 2")
    assert exact == am.Evaluation(is_correct=True, confidence=1.0, method="similarity")
    unrelated = evaluate_by_similarity("abc", "xyz")
    assert unrelated == am.Evaluation(is_correct=False, confidence=1.0, method="similarity")


def test_math_vs_words_uses_similarity() -> None:
    result = evaluate_text_answer("5", "five")
    assert (result.is_correct, result.method) == (False, "similarity")


# ------------------------------------------------------------------ dispatcher


def test_evaluate_dispatches_on_question_type() -> None:
    assert evaluate(QuestionType.MCQ, OPTIONS, CORRECT_OPTION, "b").method == "mcq"
    assert evaluate(QuestionType.SHORT, None, "3/2", "1.5").method == "sympy"
    assert evaluate(QuestionType.LONG, None, "3/2", "1.5").is_correct
    assert evaluate(QuestionType.MCQ, None, "5", "5").is_correct  # options missing: text only
