"""App-level behaviour: error envelope, 500 handling, CORS, OpenAPI/Swagger."""

import logging

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.main import create_app
from tests.api.conftest import assert_error

EXPECTED_ROUTES = {
    ("post", "/api/v1/auth/register"),
    ("post", "/api/v1/auth/login"),
    ("post", "/api/v1/auth/refresh"),
    ("get", "/api/v1/auth/me"),
    ("get", "/api/v1/units/"),
    ("get", "/api/v1/units/{unit_id}"),
    ("get", "/api/v1/units/{unit_id}/topics"),
    ("get", "/api/v1/topics/{topic_id}"),
    ("get", "/api/v1/topics/{topic_id}/formulas"),
    ("get", "/api/v1/topics/{topic_id}/questions"),
    ("post", "/api/v1/tutor/ask"),
    ("post", "/api/v1/solver/solve"),
    ("get", "/api/v1/practice/random"),
    ("post", "/api/v1/practice/submit"),
    ("get", "/api/v1/progress/"),
    ("get", "/api/v1/progress/weak-topics"),
    ("get", "/health"),
}


@pytest.fixture
def plain_client() -> TestClient:
    """No database needed for these tests."""
    return TestClient(create_app())


def test_unknown_route_uses_error_envelope(plain_client: TestClient) -> None:
    response = plain_client.get("/api/v1/does-not-exist")
    assert response.status_code == 404
    assert_error(response.json(), "not_found")


def test_wrong_method_is_405(plain_client: TestClient) -> None:
    response = plain_client.delete("/health")
    assert response.status_code == 405
    assert_error(response.json(), "method_not_allowed")


def test_unhandled_exception_is_generic_500(caplog: pytest.LogCaptureFixture) -> None:
    app: FastAPI = create_app()

    @app.get("/boom")
    def boom() -> None:
        raise RuntimeError("database password is hunter2")

    client = TestClient(app, raise_server_exceptions=False)
    with caplog.at_level(logging.ERROR):
        response = client.get("/boom")

    assert response.status_code == 500
    assert_error(response.json(), "internal_error")
    assert "hunter2" not in response.text  # internals never leak to clients
    assert "Unhandled error on GET /boom" in caplog.text  # but they are logged


def test_unmapped_http_status_gets_generic_code() -> None:
    from fastapi import HTTPException

    app = create_app()

    @app.get("/teapot")
    def teapot() -> None:
        raise HTTPException(status_code=418, detail="I'm a teapot")

    response = TestClient(app).get("/teapot")
    assert response.status_code == 418
    assert response.json() == {
        "error": {"code": "http_error", "message": "I'm a teapot", "details": None}
    }


@pytest.mark.parametrize("origin", ["http://10.0.2.2", "http://localhost"])
def test_cors_preflight_allows_flutter_origins(plain_client: TestClient, origin: str) -> None:
    response = plain_client.options(
        "/api/v1/auth/login",
        headers={
            "Origin": origin,
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "Authorization, Content-Type",
        },
    )
    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == origin
    assert "access-control-allow-credentials" not in response.headers


def test_cors_rejects_unknown_origin(plain_client: TestClient) -> None:
    response = plain_client.options(
        "/api/v1/auth/login",
        headers={"Origin": "https://evil.example", "Access-Control-Request-Method": "POST"},
    )
    assert "access-control-allow-origin" not in response.headers


def test_swagger_ui_served(plain_client: TestClient) -> None:
    response = plain_client.get("/docs")
    assert response.status_code == 200
    assert "swagger-ui" in response.text.lower()


def test_openapi_lists_every_route_and_bearer_auth(plain_client: TestClient) -> None:
    schema = plain_client.get("/openapi.json").json()
    routes = {(method, path) for path, ops in schema["paths"].items() for method in ops}
    assert routes == EXPECTED_ROUTES
    assert schema["components"]["securitySchemes"]["HTTPBearer"]["scheme"] == "bearer"
    assert "ErrorResponse" in schema["components"]["schemas"]
    me = schema["paths"]["/api/v1/auth/me"]["get"]
    assert me["security"] == [{"HTTPBearer": []}]
