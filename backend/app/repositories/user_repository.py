from functools import cache

from sqlalchemy import select

from app.core.security import hash_password, verify_password
from app.models.user import User
from app.repositories.base_repository import BaseRepository
from app.schemas.user import UserCreate, UserUpdate


class UserRepository(BaseRepository[User, UserCreate, UserUpdate]):
    model = User

    def get_by_email(self, email: str) -> User | None:
        return self.session.scalars(select(User).where(User.email == email.lower())).first()

    def create(self, data: UserCreate) -> User:
        """Create a user; the plaintext password is hashed and never stored."""
        return self._add(
            User(email=data.email, name=data.name, password_hash=hash_password(data.password))
        )

    def update(self, obj: User, data: UserUpdate) -> User:
        changes = data.model_dump(exclude_unset=True)
        password = changes.pop("password", None)
        if password is not None:
            obj.password_hash = hash_password(password)
        return super().update(obj, UserUpdate.model_validate(changes))

    def authenticate(self, email: str, password: str) -> User | None:
        """Return the active user for valid credentials, else None.

        A hash is always verified (a dummy one for unknown emails) so response time does not
        reveal which emails are registered.
        """
        user = self.get_by_email(email)
        password_ok = verify_password(
            password, user.password_hash if user is not None else _dummy_hash()
        )
        if user is None or not user.is_active or not password_ok:
            return None
        return user


@cache
def _dummy_hash() -> str:
    return hash_password("timing-equalizer-not-a-real-password")
