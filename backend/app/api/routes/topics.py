from typing import Any

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.api.deps import IdPath, SessionDep, get_current_user
from app.core.errors import NotFoundError
from app.models import Topic
from app.repositories import TopicRepository
from app.schemas.error import ErrorResponse
from app.schemas.formula import FormulaRead
from app.schemas.practice_question import PracticeQuestionRead
from app.schemas.topic import TopicRead

_ERRORS: dict[int | str, dict[str, Any]] = {
    401: {"model": ErrorResponse},
    404: {"model": ErrorResponse},
}

router = APIRouter(
    prefix="/topics",
    tags=["syllabus"],
    dependencies=[Depends(get_current_user)],
    responses=_ERRORS,
)


def _get_topic_or_404(session: Session, topic_id: int, *, with_content: bool = False) -> Topic:
    repo = TopicRepository(session)
    topic = repo.get_with_content(topic_id) if with_content else repo.get(topic_id)
    if topic is None:
        raise NotFoundError(f"Topic {topic_id} not found")
    return topic


@router.get("/{topic_id}", summary="Get one topic")
def get_topic(topic_id: IdPath, session: SessionDep) -> TopicRead:
    return TopicRead.model_validate(_get_topic_or_404(session, topic_id))


@router.get("/{topic_id}/formulas", summary="List formulas of a topic")
def list_topic_formulas(topic_id: IdPath, session: SessionDep) -> list[FormulaRead]:
    topic = _get_topic_or_404(session, topic_id, with_content=True)
    return [FormulaRead.model_validate(f) for f in topic.formulas]


@router.get("/{topic_id}/questions", summary="List practice questions of a topic")
def list_topic_questions(topic_id: IdPath, session: SessionDep) -> list[PracticeQuestionRead]:
    topic = _get_topic_or_404(session, topic_id, with_content=True)
    return [PracticeQuestionRead.model_validate(q) for q in topic.practice_questions]
