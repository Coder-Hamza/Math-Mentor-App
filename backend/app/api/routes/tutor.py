from typing import Annotated, Any

from fastapi import APIRouter, Depends

from app.api.deps import SessionDep, get_current_user
from app.schemas.ai_schemas import TutorRequest, TutorResponse
from app.schemas.error import ErrorResponse
from app.services.ai.gemini_service import GeminiService, get_gemini_service
from app.services.tutor.tutor_service import TutorService

_ERRORS: dict[int | str, dict[str, Any]] = {
    status: {"model": ErrorResponse} for status in (401, 404, 422, 429, 502, 503, 504)
}

router = APIRouter(
    prefix="/tutor",
    tags=["tutor"],
    dependencies=[Depends(get_current_user)],
    responses=_ERRORS,
)


def get_tutor_service(
    session: SessionDep, gemini: Annotated[GeminiService, Depends(get_gemini_service)]
) -> TutorService:
    return TutorService(session, gemini)


@router.post(
    "/ask",
    summary="Ask the AI tutor a question about a topic",
    description=(
        "Gemini writes a step-by-step answer (Urdu/English or English); SymPy checks every "
        "machine-checkable claim. `verification_status` is `verified`, `failed` (a likely "
        "mistake — see `warning`) or `unverifiable` (nothing could be checked). The student "
        "always gets the answer. No personal data is sent to Gemini. Max 30 s."
    ),
)
async def ask(
    request: TutorRequest,
    service: Annotated[TutorService, Depends(get_tutor_service)],
) -> TutorResponse:
    # The user is authenticated by the router dependency but deliberately NOT passed on.
    return await service.ask(request)
