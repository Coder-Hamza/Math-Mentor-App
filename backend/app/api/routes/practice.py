from typing import Annotated, Any

from fastapi import APIRouter, Depends, Query

from app.api.deps import CurrentUser, SessionDep
from app.schemas.error import ErrorResponse
from app.schemas.practice import (
    MAX_DB_INT,
    MAX_PRACTICE_COUNT,
    PracticeQuestionPublic,
    PracticeSubmitRequest,
    PracticeSubmitResponse,
)
from app.services.practice.practice_service import PracticeService

_ERRORS: dict[int | str, dict[str, Any]] = {
    status: {"model": ErrorResponse} for status in (401, 404, 422)
}

router = APIRouter(prefix="/practice", tags=["practice"], responses=_ERRORS)


def get_practice_service(session: SessionDep) -> PracticeService:
    return PracticeService(session)


PracticeServiceDep = Annotated[PracticeService, Depends(get_practice_service)]


@router.get(
    "/random",
    summary="Random practice questions (without answers)",
    description="Proofs are left out: they cannot be graded automatically.",
)
def random_questions(
    _: CurrentUser,
    service: PracticeServiceDep,
    unit_id: Annotated[int | None, Query(ge=1, le=MAX_DB_INT)] = None,
    count: Annotated[int, Query(ge=1, le=MAX_PRACTICE_COUNT)] = 5,
) -> list[PracticeQuestionPublic]:
    return service.random_questions(count=count, unit_id=unit_id)


@router.post(
    "/submit",
    summary="Submit an answer and get it graded",
    description=(
        "Graded with SymPy and string matching (no AI call). Returns the correct answer and "
        "explanation, points (easy 10 / medium 20 / hard 30, +5 under 60 s; a question pays "
        "points only the first time it is solved), the streak and an Urdu/English message."
    ),
)
def submit_answer(
    request: PracticeSubmitRequest, user: CurrentUser, service: PracticeServiceDep
) -> PracticeSubmitResponse:
    return service.submit(user.id, request)
