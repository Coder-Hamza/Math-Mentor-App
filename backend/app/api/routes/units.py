from typing import Any

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.api.deps import IdPath, SessionDep, get_current_user
from app.core.errors import NotFoundError
from app.models import Unit
from app.repositories import TopicRepository, UnitRepository
from app.schemas.error import ErrorResponse
from app.schemas.topic import TopicRead
from app.schemas.unit import UnitRead

_ERRORS: dict[int | str, dict[str, Any]] = {
    401: {"model": ErrorResponse},
    404: {"model": ErrorResponse},
}

router = APIRouter(
    prefix="/units",
    tags=["syllabus"],
    dependencies=[Depends(get_current_user)],
    responses=_ERRORS,
)


def _get_unit_or_404(session: Session, unit_id: int) -> Unit:
    unit = UnitRepository(session).get(unit_id)
    if unit is None:
        raise NotFoundError(f"Unit {unit_id} not found")
    return unit


@router.get("/", summary="List all syllabus units in order")
def list_units(session: SessionDep) -> list[UnitRead]:
    return [UnitRead.model_validate(u) for u in UnitRepository(session).list_ordered()]


@router.get("/{unit_id}", summary="Get one unit")
def get_unit(unit_id: IdPath, session: SessionDep) -> UnitRead:
    return UnitRead.model_validate(_get_unit_or_404(session, unit_id))


@router.get("/{unit_id}/topics", summary="List topics of a unit")
def list_unit_topics(unit_id: IdPath, session: SessionDep) -> list[TopicRead]:
    unit = _get_unit_or_404(session, unit_id)
    return [TopicRead.model_validate(t) for t in TopicRepository(session).list_by_unit(unit.id)]
