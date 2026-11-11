from typing import Any

from fastapi import APIRouter, status
from sqlalchemy.exc import IntegrityError

from app.api.deps import CurrentUser, SessionDep
from app.core.config import get_settings
from app.core.errors import AuthenticationError, ConflictError
from app.core.tokens import InvalidTokenError, TokenType, create_token, decode_token
from app.repositories import UserRepository
from app.schemas.auth import LoginRequest, RefreshRequest, TokenPair
from app.schemas.error import ErrorResponse
from app.schemas.user import UserCreate, UserRead

router = APIRouter(prefix="/auth", tags=["auth"])

_UNAUTHORIZED: dict[int | str, dict[str, Any]] = {401: {"model": ErrorResponse}}
_EMAIL_TAKEN = "An account with this email already exists"


def _issue_tokens(user_id: int) -> TokenPair:
    return TokenPair(
        access_token=create_token(user_id, TokenType.ACCESS),
        refresh_token=create_token(user_id, TokenType.REFRESH),
        expires_in=get_settings().access_token_expire_minutes * 60,
    )


@router.post(
    "/register",
    status_code=status.HTTP_201_CREATED,
    responses={409: {"model": ErrorResponse}},
    summary="Create a student account",
)
def register(data: UserCreate, session: SessionDep) -> UserRead:
    repo = UserRepository(session)
    if repo.get_by_email(data.email) is not None:
        raise ConflictError(_EMAIL_TAKEN)
    try:
        user = repo.create(data)
        session.commit()
    except IntegrityError:  # concurrent registration with the same email
        session.rollback()
        raise ConflictError(_EMAIL_TAKEN) from None
    return UserRead.model_validate(user)


@router.post("/login", responses=_UNAUTHORIZED, summary="Log in and get tokens")
def login(data: LoginRequest, session: SessionDep) -> TokenPair:
    user = UserRepository(session).authenticate(data.email, data.password)
    if user is None:
        raise AuthenticationError("Incorrect email or password")
    return _issue_tokens(user.id)


@router.post("/refresh", responses=_UNAUTHORIZED, summary="Exchange a refresh token")
def refresh(data: RefreshRequest, session: SessionDep) -> TokenPair:
    try:
        user_id = decode_token(data.refresh_token, TokenType.REFRESH)
    except InvalidTokenError:
        raise AuthenticationError("Invalid or expired refresh token") from None
    user = UserRepository(session).get(user_id)
    if user is None or not user.is_active:
        raise AuthenticationError("Invalid or expired refresh token")
    return _issue_tokens(user.id)


@router.get("/me", responses=_UNAUTHORIZED, summary="Current user")
def me(user: CurrentUser) -> UserRead:
    return UserRead.model_validate(user)
