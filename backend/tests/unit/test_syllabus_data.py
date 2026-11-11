"""Validate the syllabus seed data — including SymPy verification of every formula.

Accuracy-first: every formula must parse with SymPy, and every formula flagged
``identity: true`` must hold numerically at many random points.
"""

import random
from collections import Counter
from typing import Any

import pytest
from pydantic import ValidationError
from sympy import Expr, Rational, Symbol
from sympy.matrices import MatrixBase
from sympy.parsing.sympy_parser import parse_expr

from app.database.seed import FormulaSeed, SyllabusData, load_syllabus

# Sindh Board HSC-I Mathematics (DCAR) — unit number -> textbook start page (project spec).
EXPECTED_PAGES = {
    1: 1,
    2: 25,
    3: 74,
    4: 124,
    5: 162,
    6: 179,
    7: 214,
    8: 238,
    9: 267,
    10: 292,
    11: 317,
    12: 337,
}
INTEGER_SYMBOLS = {"n", "r", "k", "m"}
TOLERANCE = 1e-12
REQUIRED_TRIALS = 5
MAX_ATTEMPTS = 200

DATA = load_syllabus()


def _parse(formula: FormulaSeed) -> tuple[Any, Any | None]:
    if " = " in formula.expression:
        lhs, rhs = formula.expression.split(" = ", 1)
        return parse_expr(lhs), parse_expr(rhs)
    return parse_expr(formula.expression), None


def _max_abs_difference(difference: Any, values: dict[Symbol, Expr]) -> float:
    evaluated = difference.subs(values).doit()
    entries = list(evaluated) if isinstance(evaluated, MatrixBase) else [evaluated]
    return max(abs(complex(entry.evalf(40))) for entry in entries)


# ---------------------------------------------------------------- structure


def test_twelve_units_with_spec_page_numbers() -> None:
    assert {u.unit_number: u.page_number for u in DATA.units} == EXPECTED_PAGES


def test_units_have_titles_and_descriptions() -> None:
    for unit in DATA.units:
        assert unit.title
        assert unit.description


def test_every_unit_has_at_least_three_topics() -> None:
    counts = Counter(t.unit_number for t in DATA.topics)
    assert all(counts[n] >= 3 for n in EXPECTED_PAGES), counts


def test_every_unit_has_formulas_and_practice_questions() -> None:
    assert {f.unit_number for f in DATA.formulas} == set(EXPECTED_PAGES)
    assert {q.unit_number for q in DATA.questions} == set(EXPECTED_PAGES)


def test_difficulties_and_question_types_cover_the_range() -> None:
    assert {t.difficulty_level for t in DATA.topics} == {"easy", "medium", "hard"}
    assert {q.difficulty for q in DATA.questions} == {"easy", "medium", "hard"}
    assert {q.question_type for q in DATA.questions} == {"short", "long", "proof"}


# ---------------------------------------------------------------- SymPy verification


@pytest.mark.parametrize("formula", DATA.formulas, ids=lambda f: f.name)
def test_formula_parses_with_sympy(formula: FormulaSeed) -> None:
    lhs, rhs = _parse(formula)
    assert lhs is not None
    if formula.identity:
        assert rhs is not None, "identities must be written as 'lhs = rhs'"


IDENTITIES = [f for f in DATA.formulas if f.identity]


def test_enough_formulas_are_machine_verified() -> None:
    assert len(IDENTITIES) >= 30


@pytest.mark.parametrize("formula", IDENTITIES, ids=lambda f: f.name)
def test_identity_holds_numerically(formula: FormulaSeed) -> None:
    lhs, rhs = _parse(formula)
    difference = lhs - rhs
    symbols = sorted(difference.free_symbols, key=lambda s: s.name)
    rng = random.Random(f"{formula.unit_number}:{formula.name}")  # deterministic per formula

    successes = 0
    for _ in range(MAX_ATTEMPTS):
        values: dict[Symbol, Expr] = {
            s: Rational(rng.randint(1, 8))
            if s.name in INTEGER_SYMBOLS
            else Rational(rng.randint(1, 19), rng.randint(2, 7))
            for s in symbols
        }
        try:
            error = _max_abs_difference(difference, values)
        except TypeError, ZeroDivisionError:  # pole (zoo/nan) at this point: resample
            continue
        assert error < TOLERANCE, f"{formula.name} fails at {values}: |lhs - rhs| = {error}"
        successes += 1
        if successes >= (1 if not symbols else REQUIRED_TRIALS):
            break
    assert successes >= (1 if not symbols else REQUIRED_TRIALS), "too few valid sample points"


def test_verifier_detects_a_wrong_identity() -> None:
    """Guard against a verifier that passes everything."""
    wrong = FormulaSeed(
        unit_number=10,
        topic="x",
        name="wrong",
        expression="sin(x + y) = sin(x) + sin(y)",
        identity=True,
    )
    lhs, rhs = _parse(wrong)
    values = {Symbol("x"): Rational(1, 2), Symbol("y"): Rational(1, 3)}
    assert _max_abs_difference(lhs - rhs, values) > TOLERANCE


# ---------------------------------------------------------------- integrity validation


def _minimal(**overrides: Any) -> dict[str, Any]:
    data: dict[str, Any] = {
        "units": [{"unit_number": 1, "title": "U", "page_number": 1}],
        "topics": [{"unit_number": 1, "title": "T", "difficulty_level": "easy"}],
        "formulas": [{"unit_number": 1, "topic": "T", "name": "F", "expression": "x = 1"}],
        "questions": [
            {
                "unit_number": 1,
                "topic": "T",
                "question_text": "Q?",
                "difficulty": "easy",
                "question_type": "short",
            }
        ],
    }
    data.update(overrides)
    return data


def test_minimal_data_is_valid() -> None:
    SyllabusData.model_validate(_minimal())


@pytest.mark.parametrize(
    ("overrides", "message"),
    [
        (
            {
                "units": [
                    {"unit_number": 1, "title": "U", "page_number": 1},
                    {"unit_number": 1, "title": "U2", "page_number": 2},
                ]
            },
            "duplicate unit_number",
        ),
        (
            {"topics": [{"unit_number": 9, "title": "T", "difficulty_level": "easy"}]},
            "unknown unit 9",
        ),
        (
            {
                "units": [
                    {"unit_number": 1, "title": "U", "page_number": 1},
                    {"unit_number": 2, "title": "U2", "page_number": 5},
                ]
            },
            "unit 2 has no topics",
        ),
        (
            {"formulas": [{"unit_number": 1, "topic": "Nope", "name": "F", "expression": "x"}]},
            "formula references unknown topic",
        ),
    ],
)
def test_integrity_errors_are_reported(overrides: dict[str, Any], message: str) -> None:
    with pytest.raises(ValidationError, match=message):
        SyllabusData.model_validate(_minimal(**overrides))


def test_unknown_json_fields_rejected() -> None:
    bad = _minimal(units=[{"unit_number": 1, "title": "U", "page_number": 1, "pages": 3}])
    with pytest.raises(ValidationError):
        SyllabusData.model_validate(bad)
