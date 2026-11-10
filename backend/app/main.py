"""MathMentor AI — FastAPI application entrypoint (Phase 0 skeleton)."""

from fastapi import FastAPI

app = FastAPI(title="MathMentor AI", version="0.1.0")


@app.get("/health", tags=["system"])
def health() -> dict[str, str]:
    """Liveness probe used by the mobile app and tests."""
    return {"status": "ok"}
