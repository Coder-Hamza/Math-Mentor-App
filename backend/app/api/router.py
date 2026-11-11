from fastapi import APIRouter

from app.api.routes import auth, practice, progress, topics, tutor, units

api_router = APIRouter()
api_router.include_router(auth.router)
api_router.include_router(units.router)
api_router.include_router(topics.router)
api_router.include_router(tutor.router)
api_router.include_router(practice.router)
api_router.include_router(progress.router)
