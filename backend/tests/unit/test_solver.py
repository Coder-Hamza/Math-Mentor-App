"""Smart Question Solver: schemas, prompt, textbook pattern and the service (Gemini faked)."""

import json
import time
from typing import Any

import pytest
from pydantic import ValidationError

from app.schemas.ai_schemas import Language
from app.schemas.solver_schemas import (
    GeminiSolverAnswer,
    SolverDifficulty,
    SolverRequest,
    SolverResponse,
)
from app.services.ai.errors import AIQuotaExceededError, AITimeoutError
from app.services.ai.gemini_service import parse_solver_answer
from app.services.ai.privacy import REDACTED
from app.services.ai.solver_prompts import (
    SOLVER_SYSTEM_PROMPT,
    SolverPrompt,
    build_solver_prompt,
    render_solution,
)
from app.services.tutor import solver_service as solver_module
from app.services.tutor.solver_service import (
    UNSTRUCTURED_TIP,
    WARNING_BOOK_MISMATCH,
    WARNING_CHECK_TIMEOUT,
    WARNING_SYMPY_FAILED,
    WARNING_UNSTRUCTURED,
    SolverService,
    answers_match,
)
from tests.fakes import (
    GOOD_SOLUTION,
    FakeGenerate,
    api_error,
    make_gemini,
    make_settings,
    solution_json,
)

QUESTION = "Solve x^2 - 5x + 6 = 0"


def _service(fake: FakeGenerate, **overrides: Any) -> SolverService:
    settings = {"gemini_max_retries": 0} | overrides
    return SolverService(make_gemini(fake, **settings), make_settings(**settings))


def _request(**overrides: Any) -> SolverRequest:
    return SolverRequest.model_validate(
        {"chapter_name": "Quadratic Equations", "question": QUESTION} | overrides
    )


# ------------------------------------------------------------------ request schema


class TestSolverRequest:
    def test_defaults(self) -> None:
        request = _request()
        assert request.book_answer is None
        assert request.grade_level == "HSC-I"
        assert request.language is Language.URDU_ENGLISH

    def test_whitespace_is_stripped_and_blank_book_answer_is_none(self) -> None:
        request = _request(chapter_name="  Vectors ", question=" Find |a| ", book_answer="   ")
        assert (request.chapter_name, request.question) == ("Vectors", "Find |a|")
        assert request.book_answer is None

    @pytest.mark.parametrize(
        "overrides",
        [
            {"chapter_name": ""},
            {"chapter_name": "c" * 201},
            {"question": "   "},
            {"question": "q" * 1001},
            {"book_answer": "b" * 501},
            {"grade_level": ""},
            {"language": "french"},
            {"user_email": "a@b.com"},  # unknown fields are rejected
        ],
    )
    def test_invalid(self, overrides: dict[str, Any]) -> None:
        with pytest.raises(ValidationError):
            _request(**overrides)

    def test_limits_are_inclusive(self) -> None:
        request = _request(chapter_name="c" * 200, question="q" * 1000, book_answer="b" * 500)
        assert len(request.question) == 1000


# ------------------------------------------------------------------ prompt


class TestPrompt:
    def test_system_prompt_sets_teacher_and_rules(self) -> None:
        for phrase in (
            "You are an expert Pakistani math teacher",
            "HSC-I",
            "Sindh Board",
            "textbook pattern",
            "koi step skip mat karo",
            "same notation as Pakistani textbooks",
            "exam tip",
            '"final_answer"',
            '"checks"',
        ):
            assert phrase in SOLVER_SYSTEM_PROMPT, phrase

    def test_prompt_with_book_answer(self) -> None:
        text = build_solver_prompt(
            SolverPrompt(
                chapter="Complex Numbers", question="Simplify (3+2i)+(2)", book_answer="5 + 2i"
            )
        )
        assert "Chapter: Complex Numbers" in text
        assert "Book ka jawab hai: 5 + 2i. Isi jawab tak pohoncho." in text
        assert "Simplify (3+2i)+(2)" in text
        assert "Roman Urdu" in text
        assert "HSC-I, Sindh Board" in text

    def test_prompt_without_book_answer_and_in_english(self) -> None:
        text = build_solver_prompt(
            SolverPrompt(chapter="Vectors", question="Find |3i + 4j|", language=Language.ENGLISH)
        )
        assert "Book ka jawab" not in text
        assert "simple, clear English" in text

    def test_prompt_model_has_no_personal_fields(self) -> None:
        with pytest.raises(ValidationError):
            SolverPrompt.model_validate({"chapter": "c", "question": "q", "name": "Sana"})


# ------------------------------------------------------------------ textbook pattern


def test_render_solution_follows_the_textbook_pattern() -> None:
    text = render_solution(GeminiSolverAnswer.model_validate(GOOD_SOLUTION))
    expected_order = [
        "Sawal: Quadratic equation x^2 - 5x + 6 = 0 ko hal karein.",
        "Diya hua (Given):",
        "- x^2 - 5x + 6 = 0",
        "Poochha gaya (To Find/Prove):",
        "- x ki values",
        "Hal (Solution):",
        "Qadam 1: Factors talash karein",
        "Qadam 2: Factorise karein",
        "Formula: Factorisation: ab = 0 => a = 0 or b = 0",
        "(x - 2)(x - 3) = 0",
        "Qadam 3: Har factor ko zero rakhein",
        "Jawab: x = 2, x = 3",
        "Exam Tip: Jawab ko wapas equation mein rakh kar zaroor check karein.",
    ]
    positions = [text.index(line) for line in expected_order]
    assert positions == sorted(positions)
    assert text.count("Formula:") == 1  # only steps that use a formula


def test_render_solution_step_without_formula_or_calculation() -> None:
    steps = [{"title": "Samjhein", "explanation": "Pehle sawal samjhein."}]
    text = render_solution(GeminiSolverAnswer.model_validate(GOOD_SOLUTION | {"steps": steps}))
    lines = text.splitlines()
    step = lines.index("Qadam 1: Samjhein")
    assert lines[step + 1 : step + 4] == ["Pehle sawal samjhein.", "", "Jawab: x = 2, x = 3"]


def test_render_solution_skips_empty_given_and_to_find() -> None:
    answer = GeminiSolverAnswer.model_validate(GOOD_SOLUTION | {"given": [], "to_find": []})
    text = render_solution(answer)
    assert "Diya hua" not in text
    assert "Poochha gaya" not in text
    assert text.startswith("Sawal:")


# ------------------------------------------------------------------ parsing


def test_parse_solver_answer_accepts_fenced_json() -> None:
    result = parse_solver_answer(f"```json\n{solution_json()}\n```")
    assert result.structured
    assert result.answer is not None
    assert result.answer.method_used == "Factorisation Method"


def test_parse_solver_answer_falls_back_to_text() -> None:
    result = parse_solver_answer("Sorry, plain text only.")
    assert not result.structured
    assert result.raw_text == "Sorry, plain text only."


# ------------------------------------------------------------------ answer matching


@pytest.mark.parametrize(
    ("ours", "book"),
    [
        ("x = 2, x = 3", "x = 3, x = 2"),
        ("x = 2, x = 3", "2, 3"),
        ("5 + 2i", "2i + 5"),
        ("sqrt(2)/2", "1/√2"),
        ("0.5", "1/2"),
        ("Hence proved", "Hence proved."),
    ],
)
def test_answers_match_equivalent_forms(ours: str, book: str) -> None:
    assert answers_match(ours, book)


@pytest.mark.parametrize(
    ("ours", "book"),
    [("x = 2, x = 3", "x = 2, x = 4"), ("5 + 2i", "5 - 2i"), ("7", "8")],
)
def test_answers_match_rejects_different_answers(ours: str, book: str) -> None:
    assert not answers_match(ours, book)


# ------------------------------------------------------------------ service


async def test_solves_without_book_answer() -> None:
    fake = FakeGenerate(solution_json())
    response = await _service(fake).solve_question(_request())

    assert response.chapter == "Quadratic Equations"
    assert response.question == QUESTION
    assert [s.step_number for s in response.steps] == [1, 2, 3]
    assert response.steps[0].title == "Factors talash karein"
    assert response.steps[0].formula_used is None
    assert response.steps[1].formula_used == "Factorisation: ab = 0 => a = 0 or b = 0"
    assert response.steps[1].calculation == "(x - 2)(x - 3) = 0"
    assert response.method_used == "Factorisation Method"
    assert response.our_answer == "x = 2, x = 3"
    assert response.difficulty_level is SolverDifficulty.EASY
    assert response.pro_tip.startswith("Jawab ko wapas")
    assert response.key_concepts == ["Quadratic equation", "Factorisation"]
    assert response.sympy_verified is True
    assert response.book_answer is None
    assert response.answer_verified is False  # nothing to compare with
    assert response.warning is None
    assert response.solution.startswith("Sawal:")
    assert "Book ka jawab" not in fake.sent_text()


async def test_book_answer_that_matches_is_verified() -> None:
    fake = FakeGenerate(solution_json())
    response = await _service(fake).solve_question(_request(book_answer="x = 3 , 2"))
    assert response.answer_verified is True
    assert response.book_answer == "x = 3 , 2"
    assert response.warning is None
    assert "Book ka jawab hai: x = 3 , 2. Isi jawab tak pohoncho." in fake.sent_text()


async def test_book_answer_that_differs_is_not_verified_and_warns() -> None:
    fake = FakeGenerate(solution_json())
    response = await _service(fake).solve_question(_request(book_answer="x = 1, x = 6"))
    assert response.answer_verified is False
    assert response.warning == WARNING_BOOK_MISMATCH
    assert response.sympy_verified is True  # our own maths still checks out


async def test_wrong_maths_is_flagged() -> None:
    bad = solution_json(checks=[{"lhs": "2**2 - 5*2 + 6", "rhs": "1"}])
    response = await _service(FakeGenerate(bad)).solve_question(_request())
    assert response.sympy_verified is False
    assert response.warning == WARNING_SYMPY_FAILED


async def test_mismatch_and_wrong_maths_both_warn() -> None:
    bad = solution_json(checks=[{"lhs": "1", "rhs": "2"}])
    response = await _service(FakeGenerate(bad)).solve_question(_request(book_answer="9"))
    assert response.warning == f"{WARNING_BOOK_MISMATCH} {WARNING_SYMPY_FAILED}"


async def test_no_checks_is_not_sympy_verified_but_no_warning() -> None:
    response = await _service(FakeGenerate(solution_json(checks=[]))).solve_question(_request())
    assert response.sympy_verified is False
    assert response.warning is None


async def test_unstructured_reply_is_still_shown() -> None:
    fake = FakeGenerate("Sorry, here is some text: x = 2 or 3")
    response = await _service(fake).solve_question(_request(book_answer="2, 3"))
    assert response.solution == "Sorry, here is some text: x = 2 or 3"
    assert response.steps == []
    assert response.answer_verified is False
    assert response.sympy_verified is False
    assert response.warning == WARNING_UNSTRUCTURED
    assert response.pro_tip == UNSTRUCTURED_TIP
    assert response.book_answer == "2, 3"


async def test_gemini_budget_timeout() -> None:
    fake = FakeGenerate(5.0)  # hangs
    service = _service(fake, solver_timeout_seconds=1.1, sympy_timeout_seconds=0.1)
    start = time.perf_counter()
    with pytest.raises(AITimeoutError):
        await service.solve_question(_request())
    assert time.perf_counter() - start < 2.5


async def test_check_timeout_degrades_to_warning(monkeypatch: pytest.MonkeyPatch) -> None:
    def slow(*_: Any) -> Any:
        time.sleep(0.5)
        raise AssertionError("not reached")  # pragma: no cover

    monkeypatch.setattr(solver_module, "_run_checks", slow)
    service = _service(FakeGenerate(solution_json()), sympy_timeout_seconds=0.05)
    response = await service.solve_question(_request(book_answer="x = 2, x = 3"))
    assert response.sympy_verified is False
    assert response.answer_verified is False
    assert response.warning == f"{WARNING_BOOK_MISMATCH} {WARNING_CHECK_TIMEOUT}"
    assert response.steps  # the solution is still delivered


async def test_gemini_errors_propagate() -> None:
    with pytest.raises(AIQuotaExceededError):
        await _service(FakeGenerate(api_error(429))).solve_question(_request())


async def test_uses_solver_prompt_schema_and_longer_timeout() -> None:
    fake = FakeGenerate(solution_json())
    await _service(fake).solve_question(_request())
    config = fake.calls[0]["config"]
    assert config.system_instruction == SOLVER_SYSTEM_PROMPT
    assert config.response_schema is GeminiSolverAnswer


async def test_personal_data_is_scrubbed() -> None:
    fake = FakeGenerate(solution_json())
    await _service(fake).solve_question(
        _request(
            chapter_name="Vectors sana@example.com",
            question="Call 0300-1234567: find |3i + 4j|",
            book_answer="5, CNIC 42101-1234567-1",
        )
    )
    sent = fake.sent_text()
    for secret in ("sana@example.com", "0300-1234567", "42101-1234567-1"):
        assert secret not in sent
    assert sent.count(REDACTED) >= 3


async def test_response_is_json_serializable() -> None:
    response = await _service(FakeGenerate(solution_json())).solve_question(_request())
    body = json.loads(response.model_dump_json())
    assert set(body) == set(SolverResponse.model_fields)
    assert body["difficulty_level"] == "easy"
