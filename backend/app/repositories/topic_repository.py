from collections.abc import Sequence

from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.models.enums import Difficulty
from app.models.topic import Topic
from app.repositories.base_repository import BaseRepository
from app.schemas.topic import TopicCreate, TopicUpdate


class TopicRepository(BaseRepository[Topic, TopicCreate, TopicUpdate]):
    model = Topic

    def list_by_unit(self, unit_id: int) -> Sequence[Topic]:
        stmt = select(Topic).where(Topic.unit_id == unit_id).order_by(Topic.id)
        return self.session.scalars(stmt).all()

    def get_by_title(self, unit_id: int, title: str) -> Topic | None:
        stmt = select(Topic).where(Topic.unit_id == unit_id, Topic.title == title)
        return self.session.scalars(stmt).first()

    def list_by_difficulty(self, difficulty: Difficulty) -> Sequence[Topic]:
        stmt = select(Topic).where(Topic.difficulty_level == difficulty).order_by(Topic.id)
        return self.session.scalars(stmt).all()

    def get_with_content(self, topic_id: int) -> Topic | None:
        """Topic with its formulas and practice questions eagerly loaded."""
        stmt = (
            select(Topic)
            .where(Topic.id == topic_id)
            .options(selectinload(Topic.formulas), selectinload(Topic.practice_questions))
        )
        return self.session.scalars(stmt).first()
