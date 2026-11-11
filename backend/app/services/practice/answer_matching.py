"""Grade a student's answer against the stored answer key, without any AI call.

* **MCQ** — exact, case-insensitive match of the chosen option (its text or its letter A-D).
* **Short / long** — SymPy first: both answers are split into parts (``"x = 1, y = 2"``,
  ``"2 + 3i, 2 - 3i"``, ``"2 ± 3i"``) and every part is compared mathematically, so
  ``2i - 1`` equals ``-1 + 2i`` and ``0.5236`` equals ``pi/6``. Only when an answer is not
  mathematical (words, matrices, ...) does it fall back to string similarity.

Decimal answers are accepted when they are correctly rounded: ``9.95`` and ``9.950`` both
match ``sqrt(99)``, ``9.94`` does not. One or zero decimals must be exact.
Student text is hostile input: all parsing goes through the hardened ``verifier.parse_math``.
"""

import re
from collections.abc import Sequence
from dataclasses import dataclass
from difflib import SequenceMatcher
from typing import Final, Literal

from app.models.enums import QuestionType
from app.schemas.ai_schemas import VerificationStatus
from app.services.mathematics.verifier import (
    MathParseError,
    evaluate_constant,
    has_variables,
    verify_identity,
)

SIMILARITY_THRESHOLD: Final = 0.85
MIN_ROUNDED_DECIMALS: Final = 2  # "9.9" is not accepted for 9.95, "9.95" is
EXACT_TOL: Final = 1e-9
MCQ_LETTERS: Final = "abcd"

# Typographic characters, built with chr() so the source stays ASCII.
_MINUS_SIGNS: Final = (chr(0x2212), chr(0x2013), chr(0x2014))  # minus, en dash, em dash
_SQRT: Final = chr(0x221A)
_DEGREE: Final = chr(0x00B0)
_PLUS_MINUS: Final = chr(0x00B1)
_APPROX: Final = chr(0x2248)
_PI: Final = chr(0x03C0)

_SQRT_ARGUMENT = re.compile(_SQRT + r"\s*(\d+(?:\.\d+)?|[A-Za-z])")
_DEGREE_WORD = re.compile(r"\s*\b(?:deg|degrees?)\b", re.IGNORECASE)
_UNIT_SUFFIX = re.compile(
    r"(?<=[\d\s)])\s*(?:sq\.?\s*units?|square\s+units?|units?|cm|km|m|metres?|meters?)\.?\s*$",
    re.IGNORECASE,
)
_ANSWER_PREFIX = re.compile(r"^\s*(?:the\s+)?(?:answer|ans|jawab)\s*(?:is|=|:)?\s*", re.IGNORECASE)
_IMAGINARY_UNIT = re.compile(r"(?<![A-Za-z_])i(?![A-Za-z_0-9])")
_LABEL = re.compile(r"^\s*([A-Za-z][A-Za-z0-9_]*)\s*=\s*(.+)$")
_WORD_SEPARATORS = re.compile(r"\s+(?:and|or|aur)\s+|&", re.IGNORECASE)
_DECIMAL = re.compile(r"\d+\.(\d+)")
_THOUSANDS_SEPARATOR = re.compile(r"(?<=\d),(?=\d{3}(?!\d))")  # 2,870 (no space after)
_LETTER_CHOICE = re.compile(r"^(?:option\s*)?\(?([a-d])\)?[.):]?$")

Method = Literal["mcq", "sympy", "similarity"]


@dataclass(frozen=True)
class Evaluation:
    is_correct: bool
    confidence: float  # how sure the grader is of ``is_correct``, in [0, 1]
    method: Method


class NotMathematicalError(ValueError):
    """An answer could not be compared mathematically (fall back to text similarity)."""


# ------------------------------------------------------------------ text helpers


def normalize_text(text: str) -> str:
    """Lower-case, unify minus signs and whitespace, drop a trailing full stop."""
    for minus in _MINUS_SIGNS:
        text = text.replace(minus, "-")
    return " ".join(text.lower().split()).rstrip(".").strip()


def _compact(text: str) -> str:
    """Normalized text without spaces, for similarity and MCQ comparison."""
    return normalize_text(text).replace(" ", "")


# ------------------------------------------------------------------ MCQ


def evaluate_mcq(options: Sequence[str], correct_answer: str, student_answer: str) -> Evaluation:
    """The student may send the option text or its letter (``"B"``, ``"b)"``, ``"(b)"``)."""
    answer = normalize_text(student_answer)
    if (letter := _LETTER_CHOICE.fullmatch(answer)) is not None and len(options) == len(
        MCQ_LETTERS
    ):
        answer = normalize_text(options[MCQ_LETTERS.index(letter.group(1))])
    is_correct = answer.replace(" ", "") == _compact(correct_answer)
    return Evaluation(is_correct=is_correct, confidence=1.0, method="mcq")


# ------------------------------------------------------------------ maths


@dataclass(frozen=True)
class _Part:
    label: str | None
    expression: str  # SymPy-ready text
    tolerance: float  # absolute tolerance from the decimals written (rounding)
    angle: bool  # written with pi or a degree sign


def _to_sympy_text(text: str) -> str:
    text = _ANSWER_PREFIX.sub("", text)
    if _APPROX in text:  # "50/sqrt(3) ~ 28.87": the value after the last sign
        text = text.rsplit(_APPROX, 1)[1]
    for minus in _MINUS_SIGNS:
        text = text.replace(minus, "-")
    text = _UNIT_SUFFIX.sub("", text.strip().rstrip("."))
    text = _DEGREE_WORD.sub(_DEGREE, text)
    text = text.replace(_DEGREE, "*pi/180").replace(_PI, "pi")
    text = _SQRT_ARGUMENT.sub(r"sqrt(\1)", text).replace(_SQRT, "sqrt")
    text = _IMAGINARY_UNIT.sub("I", text)  # i is the imaginary unit (j, k stay symbols)
    return text.strip()


def _rounding_tolerance(text: str) -> float:
    """Half a unit in the last written decimal place (exact for < 2 decimals)."""
    decimals = [len(d) for d in _DECIMAL.findall(text)]
    if not decimals or min(decimals) < MIN_ROUNDED_DECIMALS:
        return 0.0
    return 0.5 * 10.0 ** -min(decimals)


def _split_top_level(text: str) -> list[str]:
    """Split on , and ; that are not inside brackets."""
    parts: list[str] = []
    depth, start = 0, 0
    for index, char in enumerate(text):
        if char in "([{":
            depth += 1
        elif char in ")]}":
            depth -= 1
        elif char in ",;" and depth == 0:
            parts.append(text[start:index])
            start = index + 1
    parts.append(text[start:])
    return parts


def _expand_plus_minus(part: str) -> list[str]:
    if part.count(_PLUS_MINUS) != 1:
        return [part]
    return [part.replace(_PLUS_MINUS, "+"), part.replace(_PLUS_MINUS, "-")]


def parse_parts(answer: str) -> list[_Part]:
    """Split an answer into labelled / unlabelled mathematical parts."""
    pieces = [
        piece.strip()
        for chunk in _split_top_level(
            _WORD_SEPARATORS.sub(",", _THOUSANDS_SEPARATOR.sub("", answer))
        )
        for piece in _expand_plus_minus(chunk)
    ]
    if not all(pieces):
        raise NotMathematicalError("empty part")
    parts: list[_Part] = []
    for piece in pieces:
        label: str | None = None
        value = piece
        if (match := _LABEL.fullmatch(piece)) is not None:
            label, value = match.group(1), match.group(2)
        expression = _to_sympy_text(value)
        try:
            has_variables(expression)  # validates (safe parse) without evaluating
        except MathParseError as exc:
            raise NotMathematicalError(str(exc)) from None
        parts.append(
            _Part(
                label=label,
                expression=expression,
                tolerance=_rounding_tolerance(value),
                angle="pi" in expression,
            )
        )
    return parts


def _values_match(a: complex, b: complex, tolerance: float) -> bool:
    return abs(a - b) <= tolerance + EXACT_TOL * max(abs(a), abs(b), 1.0)


def parts_equal(student: _Part, expected: _Part) -> bool:
    """Compare one student part with one expected part. Raises NotMathematicalError."""
    try:
        if has_variables(student.expression) or has_variables(expected.expression):
            result = verify_identity(student.expression, expected.expression)
            if result.status is VerificationStatus.UNVERIFIABLE:
                raise NotMathematicalError(result.error_message or "unverifiable")
            return result.status is VerificationStatus.VERIFIED
        given = evaluate_constant(student.expression)
        target = evaluate_constant(expected.expression)
    except MathParseError as exc:
        raise NotMathematicalError(str(exc)) from None
    tolerance = max(student.tolerance, expected.tolerance)
    if _values_match(given, target, tolerance):
        return True
    # "60" for an angle of 60 degrees / pi/3: a bare number is read as degrees.
    if expected.angle and not student.angle:
        in_degrees = given * evaluate_constant("pi/180")
        return _values_match(in_degrees, target, tolerance * evaluate_constant("pi/180").real)
    return False


def _match_unordered(student: list[_Part], expected: list[_Part]) -> bool:
    remaining = list(expected)
    for part in student:
        match = next((e for e in remaining if parts_equal(part, e)), None)
        if match is None:
            return False
        remaining.remove(match)
    return True


def compare_math(student_answer: str, correct_answer: str) -> bool:
    """True if the answers are mathematically equal. Raises NotMathematicalError."""
    expected = parse_parts(correct_answer)
    student = parse_parts(student_answer)
    if len(student) != len(expected):
        return False
    labels = [p.label for p in expected]
    distinct_labels = None not in labels and len(set(labels)) == len(labels) > 1
    if distinct_labels and all(p.label is not None for p in student):
        # "x = 1, y = 2, z = 3": match by name, in any order (R and r are different names).
        by_label = {p.label: p for p in expected}
        if {p.label for p in student} != set(by_label):
            return False
        return all(parts_equal(p, by_label[p.label]) for p in student)
    if distinct_labels:
        # Unlabelled values for a labelled answer ("1, 2, 3") are read in order.
        return all(parts_equal(s, e) for s, e in zip(student, expected, strict=True))
    # Roots, "x = 1, x = 3", single values: any order.
    return _match_unordered(student, expected)


# ------------------------------------------------------------------ similarity


def similarity(student_answer: str, correct_answer: str) -> float:
    return SequenceMatcher(None, _compact(student_answer), _compact(correct_answer)).ratio()


def evaluate_by_similarity(student_answer: str, correct_answer: str) -> Evaluation:
    ratio = similarity(student_answer, correct_answer)
    is_correct = ratio >= SIMILARITY_THRESHOLD
    return Evaluation(
        is_correct=is_correct,
        confidence=round(ratio if is_correct else 1 - ratio, 3),
        method="similarity",
    )


# ------------------------------------------------------------------ entry point


def evaluate_text_answer(correct_answer: str, student_answer: str) -> Evaluation:
    try:
        is_correct = compare_math(student_answer, correct_answer)
    except NotMathematicalError:
        return evaluate_by_similarity(student_answer, correct_answer)
    return Evaluation(is_correct=is_correct, confidence=1.0, method="sympy")


def evaluate(
    question_type: QuestionType,
    options: Sequence[str] | None,
    correct_answer: str,
    student_answer: str,
) -> Evaluation:
    if question_type is QuestionType.MCQ:
        return evaluate_mcq(options or (), correct_answer, student_answer)
    return evaluate_text_answer(correct_answer, student_answer)
