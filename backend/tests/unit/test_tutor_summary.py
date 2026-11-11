"""How per-claim SymPy results combine into the response's verification fields."""

import pytest

from app.schemas.ai_schemas import VerificationStatus
from app.services.mathematics.verifier import VerificationResult
from app.services.tutor.tutor_service import (
    WARNING_FAILED,
    WARNING_PARTIAL,
    WARNING_UNVERIFIABLE,
    summarize,
)

V, F, U = VerificationStatus.VERIFIED, VerificationStatus.FAILED, VerificationStatus.UNVERIFIABLE


def _r(status: VerificationStatus) -> VerificationResult:
    confidence = 1.0 if status is V else 0.0
    return VerificationResult(status=status, confidence=confidence, method="identity")


@pytest.mark.parametrize(
    ("statuses", "status", "verified", "confidence", "warning"),
    [
        ([], U, False, 0.0, WARNING_UNVERIFIABLE),
        ([V, V], V, True, 1.0, None),
        ([V, U], V, True, 0.5, WARNING_PARTIAL),
        ([U, U], U, False, 0.0, WARNING_UNVERIFIABLE),
        ([V, F], F, False, 0.5, WARNING_FAILED),
        ([F], F, False, 0.0, WARNING_FAILED),
        ([V, V, F, U], F, False, 0.5, WARNING_FAILED),
    ],
)
def test_summarize(
    statuses: list[VerificationStatus],
    status: VerificationStatus,
    verified: bool,
    confidence: float,
    warning: str | None,
) -> None:
    summary = summarize([_r(s) for s in statuses])
    assert (summary.status, summary.verified, summary.confidence, summary.warning) == (
        status,
        verified,
        confidence,
        warning,
    )


def test_failed_claim_is_never_reported_verified() -> None:
    for others in ([V] * 9, [V, U]):
        summary = summarize([*map(_r, others), _r(F)])
        assert summary.verified is False
        assert summary.status is F
