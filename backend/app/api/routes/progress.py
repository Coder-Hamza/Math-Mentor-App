from typing import Annotated, Any

from fastapi import APIRouter, Depends

from app.api.deps import CurrentUser, SessionDep
from app.repositories import ProgressRepository
from app.schemas.error import ErrorResponse
from app.schemas.practice import ProgressSummary, WeakTopic

_ERRORS: dict[int | str, dict[str, Any]] = {401: {"model": ErrorResponse}}

router = APIRouter(prefix="/progress", tags=["progress"], responses=_ERRORS)


def get_progress_repository(session: SessionDep) -> ProgressRepository:
    return ProgressRepository(session)


ProgressRepositoryDep = Annotated[ProgressRepository, Depends(get_progress_repository)]


@router.get("/", summary="The student's points, accuracy, streak and per-unit progress")
def get_progress(user: CurrentUser, repo: ProgressRepositoryDep) -> ProgressSummary:
    return repo.get_overall_progress(user.id)


@router.get(
    "/weak-topics",
    summary="Topics where the student's accuracy is below 60%",
)
def get_weak_topics(user: CurrentUser, repo: ProgressRepositoryDep) -> list[WeakTopic]:
    return repo.get_weak_topics(user.id)
