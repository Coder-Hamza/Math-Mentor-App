from collections.abc import Callable

import pytest
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.security import verify_password
from app.models import Difficulty, Formula, PracticeQuestion, Topic, Unit
from app.repositories import TopicRepository, UnitRepository, UserRepository
from app.repositories.base_repository import MAX_PAGE_SIZE
from app.schemas import TopicCreate, TopicUpdate, UnitCreate, UnitUpdate, UserCreate, UserUpdate

pytestmark = pytest.mark.integration


# ------------------------------------------------------------ BaseRepository (via UnitRepository)


class TestBaseRepository:
    def test_create_and_get(self, db_session: Session) -> None:
        repo = UnitRepository(db_session)
        unit = repo.create(UnitCreate(unit_number=1, title="Complex Numbers", page_number=1))
        assert unit.id is not None
        assert repo.get(unit.id) is unit

    def test_get_missing_returns_none(self, db_session: Session) -> None:
        assert UnitRepository(db_session).get(999_999) is None

    def test_get_multi_paginates_in_id_order(self, db_session: Session) -> None:
        repo = UnitRepository(db_session)
        created = [
            repo.create(UnitCreate(unit_number=n, title=f"U{n}", page_number=n))
            for n in range(1, 6)
        ]
        assert repo.get_multi(limit=2) == created[:2]
        assert repo.get_multi(offset=2, limit=2) == created[2:4]
        assert repo.get_multi(offset=4) == created[4:]
        assert repo.count() == 5

    @pytest.mark.parametrize(("offset", "limit"), [(-1, 10), (0, 0), (0, MAX_PAGE_SIZE + 1)])
    def test_get_multi_rejects_bad_paging(
        self, db_session: Session, offset: int, limit: int
    ) -> None:
        with pytest.raises(ValueError, match="limit"):
            UnitRepository(db_session).get_multi(offset=offset, limit=limit)

    def test_partial_update_changes_only_set_fields(self, db_session: Session) -> None:
        repo = UnitRepository(db_session)
        unit = repo.create(
            UnitCreate(unit_number=1, title="Old", page_number=1, description="keep me")
        )
        repo.update(unit, UnitUpdate(title="New"))
        assert (unit.title, unit.description, unit.page_number) == ("New", "keep me", 1)

    def test_update_can_explicitly_clear_nullable_field(self, db_session: Session) -> None:
        repo = UnitRepository(db_session)
        unit = repo.create(UnitCreate(unit_number=1, title="U", page_number=1, description="d"))
        repo.update(unit, UnitUpdate(description=None))
        assert unit.description is None

    def test_delete(self, db_session: Session) -> None:
        repo = UnitRepository(db_session)
        unit = repo.create(UnitCreate(unit_number=1, title="U", page_number=1))
        repo.delete(unit)
        assert repo.count() == 0

    def test_create_violating_constraint_raises(self, db_session: Session) -> None:
        repo = UnitRepository(db_session)
        repo.create(UnitCreate(unit_number=1, title="U", page_number=1))
        with pytest.raises(IntegrityError):
            repo.create(UnitCreate(unit_number=1, title="Dup", page_number=2))


# ------------------------------------------------------------ UnitRepository


class TestUnitRepository:
    def test_get_by_number(self, make_unit: Callable[..., Unit], db_session: Session) -> None:
        unit = make_unit(7)
        repo = UnitRepository(db_session)
        assert repo.get_by_number(7) is unit
        assert repo.get_by_number(8) is None

    def test_list_ordered_by_unit_number(
        self, make_unit: Callable[..., Unit], db_session: Session
    ) -> None:
        for n in (3, 1, 2):
            make_unit(n)
        assert [u.unit_number for u in UnitRepository(db_session).list_ordered()] == [1, 2, 3]

    def test_list_with_topics_eager_loads(
        self,
        make_unit: Callable[..., Unit],
        make_topic: Callable[..., Topic],
        db_session: Session,
    ) -> None:
        make_topic(make_unit(2), "B1")
        unit1 = make_unit(1)
        make_topic(unit1, "A1")
        make_topic(unit1, "A2")
        db_session.expire_all()

        units = UnitRepository(db_session).list_with_topics()

        assert [u.unit_number for u in units] == [1, 2]
        assert all("topics" in u.__dict__ for u in units)  # loaded, not lazy
        assert [t.title for t in units[0].topics] == ["A1", "A2"]


# ------------------------------------------------------------ TopicRepository


class TestTopicRepository:
    def test_create_update_via_schemas(
        self, make_unit: Callable[..., Unit], db_session: Session
    ) -> None:
        repo = TopicRepository(db_session)
        topic = repo.create(TopicCreate(unit_id=make_unit(1).id, title="Dot Product"))
        assert topic.difficulty_level is Difficulty.MEDIUM
        repo.update(topic, TopicUpdate(difficulty_level=Difficulty.HARD))
        assert topic.difficulty_level is Difficulty.HARD

    def test_list_by_unit_and_get_by_title(
        self,
        make_unit: Callable[..., Unit],
        make_topic: Callable[..., Topic],
        db_session: Session,
    ) -> None:
        unit1, unit2 = make_unit(1), make_unit(2)
        a, b = make_topic(unit1, "A"), make_topic(unit1, "B")
        make_topic(unit2, "A")
        repo = TopicRepository(db_session)

        assert repo.list_by_unit(unit1.id) == [a, b]
        assert repo.get_by_title(unit1.id, "B") is b
        assert repo.get_by_title(unit2.id, "B") is None

    def test_list_by_difficulty(
        self,
        make_unit: Callable[..., Unit],
        make_topic: Callable[..., Topic],
        db_session: Session,
    ) -> None:
        unit = make_unit(1)
        easy = make_topic(unit, "E", difficulty_level=Difficulty.EASY)
        make_topic(unit, "H", difficulty_level=Difficulty.HARD)
        assert TopicRepository(db_session).list_by_difficulty(Difficulty.EASY) == [easy]

    def test_get_with_content(
        self,
        make_unit: Callable[..., Unit],
        make_topic: Callable[..., Topic],
        db_session: Session,
    ) -> None:
        topic = make_topic(make_unit(1))
        db_session.add_all(
            [
                Formula(topic_id=topic.id, name="F", expression="x = 1"),
                PracticeQuestion(
                    topic_id=topic.id,
                    question_text="Q1",
                    correct_answer="1",
                    answer_explanation="E",
                ),
            ]
        )
        db_session.flush()
        db_session.expire_all()

        loaded = TopicRepository(db_session).get_with_content(topic.id)

        assert loaded is not None
        assert {"formulas", "practice_questions"} <= loaded.__dict__.keys()
        assert [f.name for f in loaded.formulas] == ["F"]
        assert [q.question_text for q in loaded.practice_questions] == ["Q1"]
        assert TopicRepository(db_session).get_with_content(999_999) is None


# ------------------------------------------------------------ UserRepository


@pytest.fixture
def user_repo(db_session: Session) -> UserRepository:
    return UserRepository(db_session)


def _create(repo: UserRepository, email: str = "Ali@Example.com") -> UserCreate:
    data = UserCreate(email=email, name="Ali", password="correct-horse")
    repo.create(data)
    return data


class TestUserRepository:
    def test_create_hashes_password(self, user_repo: UserRepository) -> None:
        _create(user_repo)
        user = user_repo.get_by_email("ali@example.com")
        assert user is not None
        assert user.password_hash != "correct-horse"
        assert verify_password("correct-horse", user.password_hash)

    def test_get_by_email_is_case_insensitive(self, user_repo: UserRepository) -> None:
        _create(user_repo)
        assert user_repo.get_by_email("ALI@EXAMPLE.COM") is not None
        assert user_repo.get_by_email("nobody@example.com") is None

    def test_duplicate_email_rejected(self, user_repo: UserRepository) -> None:
        _create(user_repo, "a@example.com")
        with pytest.raises(IntegrityError):
            _create(user_repo, "A@example.com")

    def test_authenticate(self, user_repo: UserRepository) -> None:
        _create(user_repo)
        assert user_repo.authenticate("ali@example.com", "correct-horse") is not None
        assert user_repo.authenticate("ali@example.com", "wrong-password") is None
        assert user_repo.authenticate("ghost@example.com", "correct-horse") is None

    def test_inactive_user_cannot_authenticate(self, user_repo: UserRepository) -> None:
        _create(user_repo)
        user = user_repo.get_by_email("ali@example.com")
        assert user is not None
        user_repo.update(user, UserUpdate(is_active=False))
        assert user_repo.authenticate("ali@example.com", "correct-horse") is None

    def test_update_password_rehashes(self, user_repo: UserRepository) -> None:
        _create(user_repo)
        user = user_repo.get_by_email("ali@example.com")
        assert user is not None
        old_hash = user.password_hash
        user_repo.update(user, UserUpdate(password="new-password-1"))
        assert user.password_hash != old_hash
        assert user_repo.authenticate("ali@example.com", "new-password-1") is user
        assert user_repo.authenticate("ali@example.com", "correct-horse") is None

    def test_update_without_password_keeps_hash(self, user_repo: UserRepository) -> None:
        _create(user_repo)
        user = user_repo.get_by_email("ali@example.com")
        assert user is not None
        old_hash = user.password_hash
        user_repo.update(user, UserUpdate(name="Ali Khan"))
        assert (user.name, user.password_hash) == ("Ali Khan", old_hash)
