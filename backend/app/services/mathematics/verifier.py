"""SymPy verification of mathematical claims (typically written by the LLM).

Safety
------
``sympy.parse_expr`` is built on ``eval``, so text from an LLM is treated as hostile:

* character allow-list (no quotes, brackets, ``:``/``;``/``@``), no ``.name`` attribute access,
  no dunder / keyword identifiers, length and digit-run limits;
* evaluation namespace contains only whitelisted SymPy objects and an **empty** ``__builtins__``;
* parsed with ``evaluate=False`` so nothing is computed while parsing, then the tree is checked
  for size, huge numeric exponents, power towers and huge factorials before any evaluation;
* evaluation is numeric (mpmath ``evalf``), never exact big-integer arithmetic.

Callers should still run verification off the event loop with a timeout (the tutor does).

Semantics
---------
* ``VERIFIED``     — the claim held at every sampled point.
* ``FAILED``       — the claim was evaluated and is wrong at ≥1 point.
* ``UNVERIFIABLE`` — could not be parsed/evaluated safely. This is *not* "wrong".
"""

import functools
import keyword
import random
import re
from typing import Any, Final, Literal

import sympy
from pydantic import BaseModel, ConfigDict, Field, computed_field
from sympy import Basic, Expr, Pow, Rational, Symbol
from sympy.parsing.sympy_parser import (
    convert_xor,
    function_exponentiation,
    implicit_application,
    implicit_multiplication,
    parse_expr,
    standard_transformations,
)

from app.schemas.ai_schemas import VerificationStatus

# ------------------------------------------------------------------ limits

SAMPLE_POINTS: Final = 5  # minimum points per identity with variables
MAX_ATTEMPTS: Final = 60  # resampling budget when a point hits a pole / domain error
MAX_EXPRESSION_LENGTH: Final = 300
MAX_NODES: Final = 400
MAX_NUMERIC_EXPONENT: Final = 1000
MAX_MAGNITUDE: Final = 1e100  # beyond this, float comparison is meaningless (poles, x - x, ...)
MAX_POWER_NESTING: Final = 2
MAX_FACTORIAL_ARGUMENT: Final = 170
PRECISION_DIGITS: Final = 30
REL_TOL: Final = 1e-9
ABS_TOL: Final = 1e-9
INTEGER_SYMBOL_NAMES: Final = frozenset({"n", "k", "r", "m"})

# ------------------------------------------------------------------ parser namespace


def _unevaluated(func: Any) -> Any:
    """``evaluate=False`` only affects operators; function calls (e.g. ``factorial(10**9)``)
    would still be computed during parsing. Build them unevaluated so limits run first."""
    return functools.partial(func, evaluate=False)


_FUNCTIONS: Final[dict[str, Any]] = {
    name: _unevaluated(getattr(sympy, name))
    for name in (
        "sin", "cos", "tan", "cot", "sec", "csc",
        "asin", "acos", "atan", "acot", "asec", "acsc", "atan2",
        "sinh", "cosh", "tanh",
        "exp", "log", "sqrt", "root", "Abs",
        "factorial", "binomial",
        "re", "im", "conjugate", "arg",
    )
}  # fmt: skip
_CONSTANTS: Final[dict[str, Any]] = {"pi": sympy.pi, "E": sympy.E, "I": sympy.I}
_ALIASES: Final[dict[str, Any]] = {
    "ln": _unevaluated(sympy.log),
    "abs": _unevaluated(sympy.Abs),
}
# Names the parser's own generated code needs. Users may not write them directly.
_PARSER_INTERNALS: Final[dict[str, Any]] = {
    "Symbol": Symbol,
    "Integer": sympy.Integer,
    "Float": sympy.Float,
    "Rational": Rational,
    "Function": sympy.Function,
    "Add": sympy.Add,  # emitted by evaluate=False
    "Mul": sympy.Mul,
    "Pow": sympy.Pow,
}
# Deliberately NOT ``implicit_multiplication_application``: its ``split_symbols`` step turns
# ``a1`` into ``a*1``, which could make ``a1 + a2 = 3*a`` "verify". Multi-letter words are
# rejected up front instead (see ``_is_known_name``).
_TRANSFORMATIONS: Final = (
    *standard_transformations,
    implicit_multiplication,
    implicit_application,
    function_exponentiation,
    convert_xor,
)

# Typographic symbols an LLM may emit, mapped to SymPy syntax (escapes keep the source ASCII).
_UNICODE_REPLACEMENTS: Final = {
    "\u2212": "-",            # minus sign
    "\u2013": "-",            # en dash
    "\u00d7": "*",            # multiplication sign
    "\u00b7": "*",            # middle dot
    "\u00f7": "/",            # division sign
    "\u03c0": "pi",           # pi
    "\u221a": "sqrt",         # square root
    "\u00b2": "**2",          # superscript two
    "\u00b3": "**3",          # superscript three
    "\u03b8": "theta",        # theta
    "\u03b1": "alpha",        # alpha
    "\u03b2": "beta_",        # beta (bare 'beta' is SymPy's beta function)
}  # fmt: skip
_ALLOWED_CHARACTERS: Final = re.compile(r"[0-9A-Za-z_+\-*/^().,\s]*")
_ATTRIBUTE_ACCESS: Final = re.compile(r"\.\s*[A-Za-z_]")
_LONG_DIGIT_RUN: Final = re.compile(r"\d{13,}")
_IDENTIFIER: Final = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
# Multi-letter names that are fine as variables. Any other multi-letter word would be split
# into single-letter symbols by implicit multiplication ("side" -> s*i*d*e), turning prose
# into a bogus expression that "fails" — so such text is reported as unverifiable instead.
_GREEK_NAMES: Final = frozenset(
    {"alpha", "beta", "beta_", "gamma", "delta", "epsilon", "theta", "phi", "psi", "omega",
     "mu", "sigma", "rho", "tau", "lamda"}
)  # fmt: skip
_SUBSCRIPTED_NAME: Final = re.compile(r"[A-Za-z]+(?:_[A-Za-z0-9]+|\d+)")  # a1, x_1, S_n, P_A


class MathParseError(ValueError):
    """The text is not a safe, parseable algebraic expression."""


class _EvaluationError(ArithmeticError):
    """The expression has no finite numeric value at this point."""


# ------------------------------------------------------------------ result


class VerificationResult(BaseModel):
    model_config = ConfigDict(frozen=True)

    status: VerificationStatus
    confidence: float = Field(ge=0, le=1)
    error_message: str | None = None
    method: Literal["identity", "numeric", "well_formed"]
    points_checked: int = 0

    @computed_field  # type: ignore[prop-decorator]
    @property
    def is_valid(self) -> bool:
        return self.status is VerificationStatus.VERIFIED


def _unverifiable(
    method: Literal["identity", "numeric", "well_formed"], reason: str
) -> VerificationResult:
    return VerificationResult(
        status=VerificationStatus.UNVERIFIABLE, confidence=0.0, error_message=reason, method=method
    )


# ------------------------------------------------------------------ parsing


def _normalize(text: str) -> str:
    for old, new in _UNICODE_REPLACEMENTS.items():
        text = text.replace(old, new)
    return text.strip()


def _check_text(text: str) -> None:
    if not text:
        raise MathParseError("empty expression")
    if len(text) > MAX_EXPRESSION_LENGTH:
        raise MathParseError(f"expression longer than {MAX_EXPRESSION_LENGTH} characters")
    if not _ALLOWED_CHARACTERS.fullmatch(text):
        raise MathParseError("expression contains unsupported characters")
    if _ATTRIBUTE_ACCESS.search(text):
        raise MathParseError("attribute access is not allowed")
    if _LONG_DIGIT_RUN.search(text):
        raise MathParseError("number too large")
    for name in _IDENTIFIER.findall(text):
        if name.startswith("_") or keyword.iskeyword(name) or name in _PARSER_INTERNALS:
            raise MathParseError(f"identifier {name!r} is not allowed")
        if not _is_known_name(name):
            raise MathParseError(f"unrecognized word {name!r} (looks like text, not math)")


def _is_known_name(name: str) -> bool:
    return (
        len(name) == 1
        or name in _FUNCTIONS
        or name in _CONSTANTS
        or name in _ALIASES
        or name in _GREEK_NAMES
        or _SUBSCRIPTED_NAME.fullmatch(name) is not None
    )


def _power_depth(node: Basic) -> int:
    """Longest chain of powers nested inside exponents (x**(y**z) has depth 2)."""
    if isinstance(node, Pow):
        return max(1 + _power_depth(node.exp), _power_depth(node.base))
    return max((_power_depth(arg) for arg in node.args), default=0)


def _check_tree(expr: Expr) -> None:
    for nodes, node in enumerate(sympy.preorder_traversal(expr), start=1):
        if nodes > MAX_NODES:
            raise MathParseError("expression too complex")
        if isinstance(node, Pow) and not node.exp.free_symbols:
            # Power depth was already bounded by the caller, so this evalf is cheap.
            exponent = complex(node.exp.evalf(15))
            if abs(exponent) > MAX_NUMERIC_EXPONENT:
                raise MathParseError("exponent too large")
        if isinstance(node, sympy.factorial | sympy.binomial):
            for arg in node.args:
                if not arg.free_symbols and abs(complex(arg.evalf(15))) > MAX_FACTORIAL_ARGUMENT:
                    raise MathParseError("factorial argument too large")


def parse_math(text: str) -> Expr:
    """Safely parse one side of an equation into an unevaluated SymPy expression."""
    cleaned = _normalize(text)
    _check_text(cleaned)
    namespace: dict[str, Any] = {
        "__builtins__": {},
        **_PARSER_INTERNALS,
        **_FUNCTIONS,
        **_CONSTANTS,
        **_ALIASES,
    }
    try:
        expr = parse_expr(
            cleaned,
            local_dict={},
            global_dict=namespace,
            transformations=_TRANSFORMATIONS,
            evaluate=False,
        )
    except Exception as exc:  # parser raises many types on malformed input
        raise MathParseError(f"could not parse expression: {type(exc).__name__}") from None
    if not isinstance(expr, Expr):
        raise MathParseError("not an algebraic expression")
    if _power_depth(expr) > MAX_POWER_NESTING:  # before any evalf in _check_tree
        raise MathParseError("power towers are not supported")
    _check_tree(expr)
    return expr


def split_equation(text: str) -> tuple[str, str] | None:
    """Split ``'lhs = rhs'`` (exactly one plain ``=``); ``None`` otherwise."""
    if any(op in text for op in ("==", "<=", ">=", "!=")) or text.count("=") != 1:
        return None
    lhs, rhs = text.split("=")
    return lhs, rhs


# ------------------------------------------------------------------ evaluation


def _evaluate(expr: Expr, point: dict[Symbol, Rational]) -> complex:
    try:
        value = expr.evalf(PRECISION_DIGITS, subs=point)
        if value.has(sympy.zoo, sympy.nan, sympy.oo, -sympy.oo) or not value.is_number:
            raise _EvaluationError
        result = complex(value)
    except (TypeError, ValueError, ZeroDivisionError, OverflowError) as exc:
        raise _EvaluationError from exc
    if result != result or not abs(result) < MAX_MAGNITUDE:  # NaN, inf, or numerically blown up
        raise _EvaluationError
    return result


def _close(a: complex, b: complex, rel_tol: float = REL_TOL, abs_tol: float = ABS_TOL) -> bool:
    return abs(a - b) <= abs_tol + rel_tol * max(abs(a), abs(b))


def _sample(rng: random.Random, symbol: Symbol) -> Rational:
    if symbol.name in INTEGER_SYMBOL_NAMES:
        return Rational(rng.randint(1, 9))
    return Rational(rng.randint(1, 29), rng.randint(2, 9))  # positive, in (0.1, 14.5)


def _describe(point: dict[Symbol, Rational]) -> str:
    return ", ".join(f"{s}={v}" for s, v in point.items()) or "constants"


# ------------------------------------------------------------------ public API


def verify_identity(lhs: str, rhs: str) -> VerificationResult:
    """Check ``lhs == rhs`` numerically at ≥ ``SAMPLE_POINTS`` random points.

    Sampling is seeded from the claim itself, so results are reproducible.
    """
    try:
        left, right = parse_math(lhs), parse_math(rhs)
    except MathParseError as exc:
        return _unverifiable("identity", str(exc))

    symbols = sorted(left.free_symbols | right.free_symbols, key=str)
    needed = SAMPLE_POINTS if symbols else 1
    rng = random.Random(f"{lhs}={rhs}")  # noqa: S311 (sampling, not cryptography)
    agree = disagree = 0
    mismatch: str | None = None

    for _ in range(MAX_ATTEMPTS):
        if agree + disagree >= needed:
            break
        point = {s: _sample(rng, s) for s in symbols}
        try:
            a, b = _evaluate(left, point), _evaluate(right, point)
        except _EvaluationError:
            continue
        if _close(a, b):
            agree += 1
        else:
            disagree += 1
            mismatch = mismatch or f"sides differ at {_describe(point)}: {a:.6g} vs {b:.6g}"

    checked = agree + disagree
    if checked < needed:
        return _unverifiable("identity", "could not evaluate at enough points")
    if disagree:
        return VerificationResult(
            status=VerificationStatus.FAILED,
            confidence=agree / checked,
            error_message=mismatch,
            method="identity",
            points_checked=checked,
        )
    return VerificationResult(
        status=VerificationStatus.VERIFIED,
        confidence=1.0,
        method="identity",
        points_checked=checked,
    )


def verify_numeric(
    expression: str, expected: float, *, tolerance: float = 1e-6
) -> VerificationResult:
    """Check a variable-free ``expression`` evaluates to ``expected`` (relative tolerance)."""
    try:
        expr = parse_math(expression)
    except MathParseError as exc:
        return _unverifiable("numeric", str(exc))
    if expr.free_symbols:
        return _unverifiable("numeric", "expression contains variables")
    try:
        value = _evaluate(expr, {})
    except _EvaluationError:
        return _unverifiable("numeric", "expression has no finite value")
    if _close(value, complex(expected), rel_tol=tolerance, abs_tol=tolerance):
        return VerificationResult(
            status=VerificationStatus.VERIFIED, confidence=1.0, method="numeric", points_checked=1
        )
    return VerificationResult(
        status=VerificationStatus.FAILED,
        confidence=0.0,
        error_message=f"evaluates to {value:.10g}, expected {expected:.10g}",
        method="numeric",
        points_checked=1,
    )


def evaluate_constant(expression: str) -> complex:
    """Numeric value of a variable-free expression; ``MathParseError`` if it has none."""
    expr = parse_math(expression)
    if expr.free_symbols:
        raise MathParseError("expression contains variables")
    try:
        return _evaluate(expr, {})
    except _EvaluationError:
        raise MathParseError("expression has no finite value") from None


def has_variables(expression: str) -> bool:
    """True if the (safely parsed) expression contains free symbols."""
    return bool(parse_math(expression).free_symbols)


def verify_expression(expression: str) -> VerificationResult:
    """``'lhs = rhs'`` is checked as an identity; anything else only for being well-formed."""
    if (sides := split_equation(expression)) is not None:
        return verify_identity(*sides)
    try:
        expr = parse_math(expression)
    except MathParseError as exc:
        return _unverifiable("well_formed", str(exc))
    rng = random.Random(expression)  # noqa: S311
    symbols = sorted(expr.free_symbols, key=str)
    for _ in range(MAX_ATTEMPTS):
        try:
            _evaluate(expr, {s: _sample(rng, s) for s in symbols})
        except _EvaluationError:
            continue
        return VerificationResult(
            status=VerificationStatus.VERIFIED,
            confidence=1.0,
            method="well_formed",
            points_checked=1,
        )
    return _unverifiable("well_formed", "expression has no finite value")
