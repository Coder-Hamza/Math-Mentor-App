"""MathMentor AI — FastAPI application factory."""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.errors import register_exception_handlers
from app.api.router import api_router
from app.core.config import Settings, get_settings

API_VERSION = "0.2.0"

OPENAPI_TAGS = [
    {"name": "auth", "description": "Register, log in, refresh tokens, current user."},
    {"name": "syllabus", "description": "Sindh Board HSC-I units, topics, formulas, questions."},
    {"name": "system", "description": "Health checks."},
]


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()
    app = FastAPI(
        title=settings.app_name,
        version=API_VERSION,
        description=(
            "Backend for the MathMentor AI tutor (Sindh Board HSC-I Mathematics). "
            "Use **Authorize** with the `access_token` from `/api/v1/auth/login`."
        ),
        openapi_tags=OPENAPI_TAGS,
    )
    # Bearer tokens travel in the Authorization header (no cookies), so credentials stay off.
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origin_list,
        allow_credentials=False,
        allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type"],
    )
    register_exception_handlers(app)
    app.include_router(api_router, prefix=settings.api_v1_prefix)

    @app.get("/health", tags=["system"])
    def health() -> dict[str, str]:
        """Liveness probe used by the mobile app and tests."""
        return {"status": "ok"}

    return app


app = create_app()
