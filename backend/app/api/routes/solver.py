from typing import Annotated, Any

from fastapi import APIRouter, Depends

from app.api.deps import get_current_user
from app.schemas.error import ErrorResponse
from app.schemas.solver_schemas import SolverRequest, SolverResponse
from app.services.ai.gemini_service import GeminiService, get_gemini_service
from app.services.tutor.solver_service import SolverService

_ERRORS: dict[int | str, dict[str, Any]] = {
    status: {"model": ErrorResponse} for status in (401, 422, 429, 502, 503, 504)
}

router = APIRouter(
    prefix="/solver",
    tags=["solver"],
    dependencies=[Depends(get_current_user)],
    responses=_ERRORS,
)


def get_solver_service(
    gemini: Annotated[GeminiService, Depends(get_gemini_service)],
) -> SolverService:
    return SolverService(gemini)


@router.post(
    "/solve",
    summary="Solve a textbook question step by step",
    description=(
        "The student gives the chapter name, the question and (optionally) the book's "
        "answer. Gemini solves it in the Pakistani textbook pattern (Sawal, Diya hua, "
        "Poochha gaya, Hal with every Qadam, Jawab, Exam Tip) in Urdu/English. SymPy checks "
        "the maths (`sympy_verified`); if a book answer is given, `answer_verified` says "
        "whether our answer is equivalent to it. No personal data is sent to Gemini. "
        "Max 45 s."
    ),
)
async def solve(
    request: SolverRequest,
    service: Annotated[SolverService, Depends(get_solver_service)],
) -> SolverResponse:
    # The user is authenticated by the router dependency but deliberately NOT passed on.
    return await service.solve_question(request)
