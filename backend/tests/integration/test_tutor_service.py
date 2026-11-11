"""TutorService end-to-end with the real database, real SymPy, and a fake Gemini transport."""

import json
import time
from typing import Any

import pytest
from sqlalchemy.orm import Session

from app.core.errors import NotFoundError
from app.database.seed import load_syllabus, seed_database
from app.repositories import TopicRepository, UnitRepository
from app.schemas.ai_schemas import Language, TutorRequest, VerificationStatus
from app.services.ai.errors import AIQuotaExceededError, AITimeoutError
from app.services.tutor import tutor_service as tutor_module
from app.services.tutor.tutor_service import (
    MAX_CHECKS,
    WARNING_FAILED,
    WARNING_UNSTRUCTURED,
    WARNING_UNVERIFIABLE,
    WARNING_VERIFY_TIMEOUT,
    TutorService,
)
from tests.fakes import (
    GOOD_ANSWER,
    FakeGenerate,
    answer_json,
    api_error,
    make_gemini,
    make_settings,
)

pytestmark = pytest.mark.integration


@pytest.fixture
def topic_id(db_session: Session) -> int:
    seed_database(db_session, load_syllabus())
    unit = UnitRepository(db_session).get_by_number(10)
    assert unit is not None
    topic = TopicRepository(db_session).get_by_title(unit.id, "Double and Half Angle Identities")
    assert topic is not None
    return topic.id


def _service(session: Session, fake: FakeGenerate, **settings: Any) -> TutorService:
    return TutorService(session, make_gemini(fake, **settings), make_settings(**settings))


def _request(topic_id: int, **overrides: Any) -> TutorRequest:
    return TutorRequest(question="Prove sin 2x = 2 sin x cos x", topic_id=topic_id, **overrides)


async def test_full_pipeline_verified(db_session: Session, topic_id: int) -> None:
    fake = FakeGenerate(answer_json())
    response = await _service(db_session, fake).ask(_request(topic_id))

    assert response.question == "Prove sin 2x = 2 sin x cos x"
    assert response.explanation == GOOD_ANSWER["explanation"]
    assert response.steps == GOOD_ANSWER["steps"]
    assert response.formulas_used == GOOD_ANSWER["formulas_used"]
    assert response.sympy_verified is True
    assert response.verification_status is VerificationStatus.VERIFIED
    assert response.verification_confidence == 1.0
    assert response.warning is None
    assert response.topic == "Double and Half Angle Identities"
    assert response.unit == "Trigonometric Identities of Sum and Difference of Angles"


async def test_prompt_uses_database_context(db_session: Session, topic_id: int) -> None:
    fake = FakeGenerate()
    await _service(db_session, fake).ask(_request(topic_id, language=Language.ENGLISH))
    contents = fake.calls[0]["contents"]
    assert "Unit: Unit 10: Trigonometric Identities of Sum and Difference of Angles" in contents
    assert "Topic: Double and Half Angle Identities" in contents
    # Seeded formulas for this topic are offered as reference.
    assert "Sine of a double angle: sin(2*x) = 2*sin(x)*cos(x)" in contents
    assert "simple, clear English" in contents


async def test_wrong_math_is_flagged_not_hidden(db_session: Session, topic_id: int) -> None:
    wrong = answer_json(checks=[{"lhs": "sin(2*x)", "rhs": "2*sin(x)"}])
    response = await _service(db_session, FakeGenerate(wrong)).ask(_request(topic_id))
    assert response.sympy_verified is False
    assert response.verification_status is VerificationStatus.FAILED
    assert response.warning == WARNING_FAILED
    assert response.steps  # the student still gets the answer


async def test_no_checks_is_unverifiable_with_warning(db_session: Session, topic_id: int) -> None:
    response = await _service(db_session, FakeGenerate(answer_json(checks=[]))).ask(
        _request(topic_id)
    )
    assert (response.verification_status, response.sympy_verified) == (
        VerificationStatus.UNVERIFIABLE,
        False,
    )
    assert response.warning == WARNING_UNVERIFIABLE
    assert response.verification_confidence == 0.0


async def test_unparseable_checks_are_unverifiable_not_failed(
    db_session: Session, topic_id: int
) -> None:
    checks = [{"lhs": "the left side", "rhs": "the right side"}]
    response = await _service(db_session, FakeGenerate(answer_json(checks=checks))).ask(
        _request(topic_id)
    )
    assert response.verification_status is VerificationStatus.UNVERIFIABLE


async def test_partially_checkable_answer(db_session: Session, topic_id: int) -> None:
    checks = [{"lhs": "sin(2*x)", "rhs": "2*sin(x)*cos(x)"}, {"lhs": "???", "rhs": "1"}]
    response = await _service(db_session, FakeGenerate(answer_json(checks=checks))).ask(
        _request(topic_id)
    )
    assert response.sympy_verified is True
    assert response.verification_confidence == 0.5
    assert response.warning is not None


async def test_plain_text_reply_still_answers(db_session: Session, topic_id: int) -> None:
    response = await _service(db_session, FakeGenerate("sin 2x = 2 sin x cos x, done.")).ask(
        _request(topic_id)
    )
    assert response.explanation == "sin 2x = 2 sin x cos x, done."
    assert response.steps == []
    assert response.verification_status is VerificationStatus.UNVERIFIABLE
    assert response.warning == WARNING_UNSTRUCTURED


async def test_only_first_max_checks_are_verified(db_session: Session, topic_id: int) -> None:
    checks = [{"lhs": "1", "rhs": "1"}] * MAX_CHECKS + [{"lhs": "1", "rhs": "2"}]
    response = await _service(db_session, FakeGenerate(answer_json(checks=checks))).ask(
        _request(topic_id)
    )
    assert response.verification_status is VerificationStatus.VERIFIED


async def test_unknown_topic_is_not_found_and_gemini_not_called(db_session: Session) -> None:
    fake = FakeGenerate()
    with pytest.raises(NotFoundError):
        await _service(db_session, fake).ask(TutorRequest(question="Q", topic_id=999_999))
    assert fake.calls == []


async def test_gemini_budget_timeout(db_session: Session, topic_id: int) -> None:
    fake = FakeGenerate(5.0)  # hangs
    service = _service(db_session, fake, tutor_timeout_seconds=1.1, sympy_timeout_seconds=0.1)
    start = time.perf_counter()
    with pytest.raises(AITimeoutError):
        await service.ask(_request(topic_id))
    assert time.perf_counter() - start < 2.5


async def test_verification_timeout_degrades_to_warning(
    db_session: Session, topic_id: int, monkeypatch: pytest.MonkeyPatch
) -> None:
    def slow(checks: Any) -> Any:
        time.sleep(0.5)
        return []

    monkeypatch.setattr(tutor_module, "_verify_all", slow)
    service = _service(db_session, FakeGenerate(), sympy_timeout_seconds=0.05)
    response = await service.ask(_request(topic_id))
    assert response.verification_status is VerificationStatus.UNVERIFIABLE
    assert response.warning == WARNING_VERIFY_TIMEOUT
    assert response.explanation  # answer still delivered


async def test_gemini_errors_propagate_as_ai_errors(db_session: Session, topic_id: int) -> None:
    with pytest.raises(AIQuotaExceededError):
        await _service(db_session, FakeGenerate(api_error(429))).ask(_request(topic_id))


async def test_response_is_json_serializable(db_session: Session, topic_id: int) -> None:
    response = await _service(db_session, FakeGenerate()).ask(_request(topic_id))
    data = json.loads(response.model_dump_json())
    assert data["verification_status"] == "verified"
