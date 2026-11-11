from fastapi import APIRouter

from app.api.routes import auth, topics, units

api_router = APIRouter()
api_router.include_router(auth.router)
api_router.include_router(units.router)
api_router.include_router(topics.router)
