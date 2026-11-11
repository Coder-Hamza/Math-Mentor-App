"""SymPy verifier: correctness, 'unverifiable is not wrong', and hostile-input safety."""

import time

import pytest

from app.schemas.ai_schemas import VerificationStatus
from app.services.mathematics.verifier import (
    SAMPLE_POINTS,
    MathParseError,
    parse_math,
    split_equation,
    verify_expression,
    verify_identity,
    verify_numeric,
)

VERIFIED = VerificationStatus.VERIFIED
FAILED = VerificationStatus.FAILED
UNVERIFIABLE = VerificationStatus.UNVERIFIABLE


# ------------------------------------------------------------------ correct identities

CORRECT_IDENTITIES = [
    ("sin(2*x)", "2*sin(x)*cos(x)"),
    ("cos(x - y)", "cos(x)*cos(y) + sin(x)*sin(y)"),
    ("tan(A + B)", "(tan(A) + tan(B))/(1 - tan(A)*tan(B))"),
    ("(a + b)**2", "a**2 + 2*a*b + b**2"),
    ("(a+b)^3", "a^3 + 3a^2 b + 3a b^2 + b^3"),  # ^ and implicit multiplication
    ("x**-1", "1/x"),
    ("log(a*b)", "log(a) + log(b)"),
    ("ln(x**2)", "2*ln(x)"),
    ("(x + I*y)*(x - I*y)", "x**2 + y**2"),
    ("binomial(n, r) + binomial(n, r - 1)", "binomial(n + 1, r)"),
    ("asin(x) + acos(x)", "pi/2"),
    ("abs(-x)", "x"),
]


@pytest.mark.parametrize(("lhs", "rhs"), CORRECT_IDENTITIES)
def test_correct_identity_verified_at_five_points(lhs: str, rhs: str) -> None:
    result = verify_identity(lhs, rhs)
    assert result.status is VERIFIED, result.error_message
    assert result.is_valid is True
    assert result.confidence == 1.0
    assert result.points_checked >= SAMPLE_POINTS
    assert result.error_message is None


@pytest.mark.parametrize(
    ("lhs", "rhs"),
    [
        ("I**2", "-1"),
        ("(3 + 4*I)/(1 - 2*I)", "-1 + 2*I"),
        ("2**2 - 5*2 + 6", "0"),  # answer substituted back into the equation
        ("factorial(5)", "120"),
        ("sqrt(2)**2", "2"),
    ],
)
def test_numeric_fact_needs_one_point(lhs: str, rhs: str) -> None:
    result = verify_identity(lhs, rhs)
    assert (result.status, result.points_checked) == (VERIFIED, 1)


# ------------------------------------------------------------------ wrong identities

WRONG_IDENTITIES = [
    ("sin(x + y)", "sin(x) + sin(y)"),
    ("(a + b)**2", "a**2 + b**2"),
    ("cos(2*x)", "2*cos(x)"),
    ("log(a + b)", "log(a) + log(b)"),
    ("3**2 - 5*3 + 7", "0"),
    ("binomial(n, r)", "factorial(n)/factorial(r)"),
]


@pytest.mark.parametrize(("lhs", "rhs"), WRONG_IDENTITIES)
def test_wrong_identity_fails_with_counterexample(lhs: str, rhs: str) -> None:
    result = verify_identity(lhs, rhs)
    assert result.status is FAILED
    assert result.is_valid is False
    assert result.confidence < 1.0
    assert result.error_message is not None
    assert "differ" in result.error_message


def test_identity_true_only_at_some_points_fails_with_partial_confidence() -> None:
    # x**2 == x only at 0 and 1 — a single matching point must not make it "verified".
    result = verify_identity("x**2", "x")
    assert result.status is FAILED
    assert 0 <= result.confidence < 1


def test_results_are_deterministic() -> None:
    assert verify_identity("sin(x+y)", "sin(x)+sin(y)") == verify_identity(
        "sin(x+y)", "sin(x)+sin(y)"
    )


# ------------------------------------------------------------------ unverifiable != wrong


@pytest.mark.parametrize(
    ("lhs", "rhs"),
    [
        ("the answer is 5", "5"),
        ("", "1"),
        ("x +* 2", "1"),
        ("(x + 1", "1"),
        ("Matrix([[1]])", "1"),  # brackets not supported
        ("1/(x - x)", "0"),  # undefined everywhere
        ("x < 2", "1"),
        ("the left side", "the right side"),  # prose must not become s*i*d*e and "fail"
        ("area of triangle", "half base times height"),
        ("2ab", "2*a*b"),  # ambiguous multi-letter name: unverifiable, never a false "wrong"
    ],
)
def test_unparseable_or_undefined_is_unverifiable_not_wrong(lhs: str, rhs: str) -> None:
    result = verify_identity(lhs, rhs)
    assert result.status is UNVERIFIABLE
    assert result.is_valid is False
    assert result.confidence == 0.0
    assert result.error_message


@pytest.mark.parametrize(
    ("lhs", "rhs"),
    [
        ("a1 + a2", "a2 + a1"),
        ("S_n", "S_n"),
        ("theta + alpha", "alpha + theta"),
        ("sin(theta)**2 + cos(theta)**2", "1"),
        ("ln(E)", "1"),
    ],
)
def test_subscripted_and_greek_names_are_accepted(lhs: str, rhs: str) -> None:
    assert verify_identity(lhs, rhs).status is VERIFIED


def test_subscripted_names_are_independent_variables() -> None:
    """Regression: a1 must not be parsed as a*1 (which would 'verify' a1 + a2 = 3a)."""
    assert verify_identity("a1 + a2", "3*a").status is FAILED
    assert verify_identity("x_1*x_2", "x_2*x_1").status is VERIFIED


def test_unicode_math_is_normalized() -> None:
    assert verify_identity("cos(x)\u00b2 + sin(x)\u00b2", "1").status is VERIFIED
    assert verify_identity("2\u00d73 \u2212 1", "5").status is VERIFIED
    assert verify_identity("\u221a(4)", "2").status is VERIFIED
    assert verify_identity("sin(\u03c0/2)", "1").status is VERIFIED


# ------------------------------------------------------------------ safety


@pytest.mark.parametrize(
    "hostile",
    [
        "__import__('os').system('echo pwned')",
        "x.__class__",
        "().__class__.__bases__",
        "lambda: 1",
        "exec(x)",  # becomes an undefined *symbolic* function, never Python's exec
        "Symbol(x)",
        "Function(f)",
        "open(x)",
        "1; 2",
        "x[0]",
        "{1: 2}",
        "'text'",
        "x @ y",
        "import os",
        "_private",
    ],
)
def test_hostile_input_is_never_executed(hostile: str) -> None:
    result = verify_identity(hostile, "1")
    assert result.status in {UNVERIFIABLE, FAILED}  # never VERIFIED, never an exception


@pytest.mark.parametrize(
    "expensive",
    [
        "9**9**9**9",
        "x**(x**(x**x))",
        "2**(10**5)",
        "factorial(100000)",
        "factorial(999999999999)",
        "binomial(10**12, 3)",
        "12345678901234567890",
        "x" + "+x" * 200,  # too many nodes / too long
    ],
)
def test_expensive_input_rejected_quickly(expensive: str) -> None:
    start = time.perf_counter()
    result = verify_identity(expensive, "1")
    assert result.status is UNVERIFIABLE
    assert time.perf_counter() - start < 1.0


def test_node_limit_reachable_within_length_limit() -> None:
    # "-x" becomes Mul(-1, x): ~3 nodes per 2 characters, so 299 chars exceed MAX_NODES.
    with pytest.raises(MathParseError, match="too complex"):
        parse_math("x" + "-x" * 149)


def test_evaluation_errors_become_evaluation_failures() -> None:
    from app.services.mathematics import verifier

    class Exploding:
        def evalf(self, *args: object, **kwargs: object) -> object:
            raise ValueError("boom")

    with pytest.raises(verifier._EvaluationError):
        verifier._evaluate(Exploding(), {})  # type: ignore[arg-type]


def test_parse_math_raises_typed_error() -> None:
    with pytest.raises(MathParseError):
        parse_math("x.__class__")


def test_parse_math_rejects_non_expression_results() -> None:
    with pytest.raises(MathParseError, match="not an algebraic expression"):
        parse_math("1, 2")


# ------------------------------------------------------------------ verify_numeric


def test_verify_numeric_correct() -> None:
    result = verify_numeric("sqrt(2)", 1.41421356237)
    assert (result.status, result.method, result.is_valid) == (VERIFIED, "numeric", True)


def test_verify_numeric_wrong() -> None:
    result = verify_numeric("sqrt(2)", 1.5)
    assert result.status is FAILED
    assert result.error_message is not None
    assert "expected 1.5" in result.error_message


def test_verify_numeric_custom_tolerance() -> None:
    assert verify_numeric("pi", 3.14, tolerance=1e-2).status is VERIFIED
    assert verify_numeric("pi", 3.14).status is FAILED


@pytest.mark.parametrize(
    ("expression", "reason"),
    [("x + 1", "contains variables"), ("1/0", "no finite value"), ("1 +", "parse")],
)
def test_verify_numeric_unverifiable(expression: str, reason: str) -> None:
    result = verify_numeric(expression, 1.0)
    assert result.status is UNVERIFIABLE
    assert result.error_message is not None
    assert reason in result.error_message


# ------------------------------------------------------------------ verify_expression


def test_verify_expression_with_equals_checks_identity() -> None:
    assert verify_expression("sin(2*x) = 2*sin(x)*cos(x)").status is VERIFIED
    assert verify_expression("sin(2*x) = 2*sin(x)").status is FAILED


def test_verify_expression_without_equals_checks_well_formed() -> None:
    result = verify_expression("x**2 + 2*x + 1")
    assert (result.status, result.method) == (VERIFIED, "well_formed")


@pytest.mark.parametrize("expression", ["x +", "1/(x - x)"])
def test_verify_expression_malformed_is_unverifiable(expression: str) -> None:
    assert verify_expression(expression).status is UNVERIFIABLE


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("a = b", ("a ", " b")),
        ("a == b", None),
        ("a <= b", None),
        ("a = b = c", None),
        ("a + b", None),
    ],
)
def test_split_equation(text: str, expected: tuple[str, str] | None) -> None:
    assert split_equation(text) == expected
