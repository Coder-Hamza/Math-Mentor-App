from datetime import timedelta

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from app.core.tokens import TokenType, create_token, decode_token
from app.models import User
from app.repositories import UserRepository
from app.schemas import UserUpdate
from tests.api.conftest import EMAIL, PASSWORD, assert_error

pytestmark = pytest.mark.integration

REGISTER = "/api/v1/auth/register"
LOGIN = "/api/v1/auth/login"
REFRESH = "/api/v1/auth/refresh"
ME = "/api/v1/auth/me"


def _bearer(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


# ------------------------------------------------------------------ register


class TestRegister:
    def test_creates_user_and_hides_password(self, client: TestClient) -> None:
        response = client.post(
            REGISTER, json={"email": "New@Example.com", "name": "Sana", "password": PASSWORD}
        )
        assert response.status_code == 201
        body = response.json()
        assert body["email"] == "new@example.com"
        assert body["name"] == "Sana"
        assert body["is_active"] is True
        assert set(body) == {"id", "email", "name", "created_at", "is_active"}
        assert PASSWORD not in response.text

    def test_registered_user_can_log_in(self, client: TestClient) -> None:
        client.post(REGISTER, json={"email": "a@example.com", "name": "A", "password": PASSWORD})
        response = client.post(LOGIN, json={"email": "a@example.com", "password": PASSWORD})
        assert response.status_code == 200

    def test_duplicate_email_is_409(self, client: TestClient, user: User) -> None:
        response = client.post(
            REGISTER, json={"email": EMAIL.upper(), "name": "Dup", "password": PASSWORD}
        )
        assert response.status_code == 409
        assert_error(response.json(), "conflict")

    def test_concurrent_duplicate_is_409(
        self, client: TestClient, user: User, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """Simulates a race: the pre-check misses, the unique index catches it."""
        monkeypatch.setattr(UserRepository, "get_by_email", lambda self, email: None)
        response = client.post(REGISTER, json={"email": EMAIL, "name": "Dup", "password": PASSWORD})
        assert response.status_code == 409
        assert_error(response.json(), "conflict")

    @pytest.mark.parametrize(
        "payload",
        [
            {"email": "not-an-email", "name": "A", "password": PASSWORD},
            {"email": "a@example.com", "name": "A", "password": "short"},
            {"email": "a@example.com", "name": "", "password": PASSWORD},
            {"email": "a@example.com", "password": PASSWORD},
            {"email": "a@example.com", "name": "A", "password": PASSWORD, "role": "admin"},
        ],
    )
    def test_invalid_payload_is_422(self, client: TestClient, payload: dict[str, str]) -> None:
        response = client.post(REGISTER, json=payload)
        assert response.status_code == 422
        body = response.json()
        assert_error(body, "validation_error")
        assert body["error"]["details"]
        assert all(set(d) == {"loc", "msg", "type"} for d in body["error"]["details"])

    def test_validation_error_never_echoes_password(self, client: TestClient) -> None:
        response = client.post(
            REGISTER, json={"email": "bad", "name": "A", "password": "secret-pw-123"}
        )
        assert response.status_code == 422
        assert "secret-pw-123" not in response.text


# ------------------------------------------------------------------ login


class TestLogin:
    def test_returns_token_pair(self, client: TestClient, user: User) -> None:
        response = client.post(LOGIN, json={"email": EMAIL, "password": PASSWORD})
        assert response.status_code == 200
        body = response.json()
        assert body["token_type"] == "bearer"
        assert body["expires_in"] > 0
        assert decode_token(body["access_token"], TokenType.ACCESS) == user.id
        assert decode_token(body["refresh_token"], TokenType.REFRESH) == user.id

    def test_email_is_case_insensitive(self, client: TestClient, user: User) -> None:
        response = client.post(LOGIN, json={"email": EMAIL.upper(), "password": PASSWORD})
        assert response.status_code == 200

    @pytest.mark.parametrize(
        ("email", "password"),
        [(EMAIL, "wrong-password"), ("nobody@example.com", PASSWORD)],
    )
    def test_bad_credentials_are_401_with_same_message(
        self, client: TestClient, user: User, email: str, password: str
    ) -> None:
        response = client.post(LOGIN, json={"email": email, "password": password})
        assert response.status_code == 401
        assert_error(response.json(), "not_authenticated")
        assert response.json()["error"]["message"] == "Incorrect email or password"
        assert response.headers["www-authenticate"] == "Bearer"

    def test_inactive_user_cannot_log_in(
        self, client: TestClient, user: User, db_session: Session
    ) -> None:
        UserRepository(db_session).update(user, UserUpdate(is_active=False))
        response = client.post(LOGIN, json={"email": EMAIL, "password": PASSWORD})
        assert response.status_code == 401

    def test_missing_fields_are_422(self, client: TestClient) -> None:
        response = client.post(LOGIN, json={"email": EMAIL})
        assert response.status_code == 422
        assert_error(response.json(), "validation_error")


# ------------------------------------------------------------------ refresh


class TestRefresh:
    def test_issues_new_pair(self, client: TestClient, user: User) -> None:
        refresh_token = create_token(user.id, TokenType.REFRESH)
        response = client.post(REFRESH, json={"refresh_token": refresh_token})
        assert response.status_code == 200
        new_access = response.json()["access_token"]
        assert client.get(ME, headers=_bearer(new_access)).status_code == 200

    def test_access_token_cannot_be_used_to_refresh(self, client: TestClient, user: User) -> None:
        access = create_token(user.id, TokenType.ACCESS)
        response = client.post(REFRESH, json={"refresh_token": access})
        assert response.status_code == 401
        assert_error(response.json(), "not_authenticated")

    def test_expired_refresh_token_is_401(self, client: TestClient, user: User) -> None:
        expired = create_token(user.id, TokenType.REFRESH, expires_delta=timedelta(seconds=-1))
        assert client.post(REFRESH, json={"refresh_token": expired}).status_code == 401

    def test_refresh_for_deleted_user_is_401(self, client: TestClient) -> None:
        orphan = create_token(999_999, TokenType.REFRESH)
        assert client.post(REFRESH, json={"refresh_token": orphan}).status_code == 401

    def test_refresh_for_inactive_user_is_401(
        self, client: TestClient, user: User, db_session: Session
    ) -> None:
        token = create_token(user.id, TokenType.REFRESH)
        UserRepository(db_session).update(user, UserUpdate(is_active=False))
        assert client.post(REFRESH, json={"refresh_token": token}).status_code == 401


# ------------------------------------------------------------------ me


class TestMe:
    def test_returns_current_user(
        self, client: TestClient, user: User, auth_headers: dict[str, str]
    ) -> None:
        response = client.get(ME, headers=auth_headers)
        assert response.status_code == 200
        assert response.json()["email"] == EMAIL
        assert "password_hash" not in response.json()

    def test_full_flow_login_then_me(self, client: TestClient, user: User) -> None:
        tokens = client.post(LOGIN, json={"email": EMAIL, "password": PASSWORD}).json()
        response = client.get(ME, headers=_bearer(tokens["access_token"]))
        assert response.json()["id"] == user.id

    def test_no_token_is_401(self, client: TestClient) -> None:
        response = client.get(ME)
        assert response.status_code == 401
        assert_error(response.json(), "not_authenticated")
        assert response.headers["www-authenticate"] == "Bearer"

    @pytest.mark.parametrize(
        "header",
        ["Bearer garbage", "Basic dXNlcjpwYXNz", "Bearer ", "token-without-scheme"],
    )
    def test_bad_authorization_header_is_401(self, client: TestClient, header: str) -> None:
        response = client.get(ME, headers={"Authorization": header})
        assert response.status_code == 401
        assert_error(response.json(), "not_authenticated")

    def test_refresh_token_cannot_access_protected_route(
        self, client: TestClient, user: User
    ) -> None:
        refresh_token = create_token(user.id, TokenType.REFRESH)
        assert client.get(ME, headers=_bearer(refresh_token)).status_code == 401

    def test_expired_access_token_is_401(self, client: TestClient, user: User) -> None:
        expired = create_token(user.id, TokenType.ACCESS, expires_delta=timedelta(seconds=-1))
        assert client.get(ME, headers=_bearer(expired)).status_code == 401

    def test_token_of_deleted_user_is_401(self, client: TestClient) -> None:
        orphan = create_token(999_999, TokenType.ACCESS)
        assert client.get(ME, headers=_bearer(orphan)).status_code == 401

    def test_deactivated_user_loses_access(
        self,
        client: TestClient,
        user: User,
        auth_headers: dict[str, str],
        db_session: Session,
    ) -> None:
        UserRepository(db_session).update(user, UserUpdate(is_active=False))
        assert client.get(ME, headers=auth_headers).status_code == 401
