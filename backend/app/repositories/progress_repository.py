"""Student progress: per-topic totals, the attempt log, streaks and summaries.

Like every repository this flushes but never commits; ``PracticeService`` owns the
transaction (and locks the user row, so one student's submissions are applied one at a time).
"""

from collections import defaultdict
from datetime import UTC, datetime
from typing import Final

from sqlalchemy import exists, func, select

from app.models import PracticeAttempt, PracticeQuestion, StudentProgress, Topic, Unit
from app.repositories.base_repository import BaseRepository
from app.repositories.practice_question_repository import gradable_clause
from app.schemas.practice import ProgressSummary, UnitProgress, WeakTopic
from app.schemas.student_progress import StudentProgressCreate, StudentProgressUpdate

WEAK_TOPIC_THRESHOLD: Final = 60.0  # accuracy (%) below which a topic is "weak"


def _percent(part: float, whole: float) -> float:
    return round(100 * part / whole, 1) if whole else 0.0


class ProgressRepository(
    BaseRepository[StudentProgress, StudentProgressCreate, StudentProgressUpdate]
):
    model = StudentProgress

    # ------------------------------------------------------------ per topic

    def get_progress(self, user_id: int, topic_id: int) -> StudentProgress | None:
        stmt = select(StudentProgress).where(
            StudentProgress.user_id == user_id, StudentProgress.topic_id == topic_id
        )
        return self.session.scalars(stmt).first()

    def get_or_create_progress(self, user_id: int, topic_id: int) -> StudentProgress:
        progress = self.get_progress(user_id, topic_id)
        if progress is None:
            progress = self._add(StudentProgress(user_id=user_id, topic_id=topic_id))
        return progress

    def update_after_attempt(
        self, user_id: int, topic_id: int, *, is_correct: bool, points: int
    ) -> StudentProgress:
        """Count one attempt on a topic; ``score`` becomes the topic accuracy (%)."""
        if points < 0:
            raise ValueError("points must not be negative")
        progress = self.get_or_create_progress(user_id, topic_id)
        progress.attempts += 1
        progress.correct_count += int(is_correct)
        progress.points += points
        progress.score = round(100 * progress.correct_count / progress.attempts, 2)
        progress.last_attempted = datetime.now(UTC)
        self.session.flush()
        return progress

    # ------------------------------------------------------------ attempt log

    def record_attempt(
        self,
        user_id: int,
        question_id: int,
        *,
        is_correct: bool,
        points: int,
        time_taken_seconds: int,
    ) -> PracticeAttempt:
        attempt = PracticeAttempt(
            user_id=user_id,
            question_id=question_id,
            is_correct=is_correct,
            points_earned=points,
            time_taken_seconds=time_taken_seconds,
        )
        self.session.add(attempt)
        self.session.flush()
        return attempt

    def has_solved(self, user_id: int, question_id: int) -> bool:
        """Has the student ever answered this question correctly?"""
        stmt = select(
            exists().where(
                PracticeAttempt.user_id == user_id,
                PracticeAttempt.question_id == question_id,
                PracticeAttempt.is_correct.is_(True),
            )
        )
        return bool(self.session.scalar(stmt))

    def current_streak(self, user_id: int) -> int:
        """Correct answers since the student's last wrong one."""
        last_wrong = (
            select(func.max(PracticeAttempt.id))
            .where(PracticeAttempt.user_id == user_id, PracticeAttempt.is_correct.is_(False))
            .scalar_subquery()
        )
        stmt = select(func.count()).where(
            PracticeAttempt.user_id == user_id,
            PracticeAttempt.id > func.coalesce(last_wrong, 0),
        )
        return self.session.scalar(stmt) or 0

    def total_points(self, user_id: int) -> int:
        stmt = select(func.coalesce(func.sum(StudentProgress.points), 0)).where(
            StudentProgress.user_id == user_id
        )
        return int(self.session.scalar(stmt) or 0)

    # ------------------------------------------------------------ summaries

    def get_overall_progress(self, user_id: int) -> ProgressSummary:
        totals = self.session.execute(
            select(
                func.coalesce(func.sum(StudentProgress.points), 0),
                func.coalesce(func.sum(StudentProgress.attempts), 0),
                func.coalesce(func.sum(StudentProgress.correct_count), 0),
            ).where(StudentProgress.user_id == user_id)
        ).one()
        points, attempted, correct = (int(value) for value in totals)
        return ProgressSummary(
            total_points=points,
            total_attempted=attempted,
            total_correct=correct,
            accuracy_percent=_percent(correct, attempted),
            current_streak=self.current_streak(user_id),
            units_progress=self._units_progress(user_id),
        )

    def get_unit_progress(self, user_id: int, unit_id: int) -> UnitProgress | None:
        """Progress in one unit, or ``None`` if the unit does not exist."""
        units = self._units_progress(user_id, unit_id=unit_id)
        return units[0] if units else None

    def get_weak_topics(self, user_id: int) -> list[WeakTopic]:
        """Attempted topics with accuracy below ``WEAK_TOPIC_THRESHOLD``, weakest first."""
        stmt = (
            select(StudentProgress, Topic, Unit)
            .join(Topic, StudentProgress.topic_id == Topic.id)
            .join(Unit, Topic.unit_id == Unit.id)
            .where(
                StudentProgress.user_id == user_id,
                StudentProgress.attempts > 0,
                StudentProgress.score < WEAK_TOPIC_THRESHOLD,
            )
            .order_by(StudentProgress.score, Unit.unit_number, Topic.id)
        )
        return [
            WeakTopic(
                topic_id=topic.id,
                topic_title=topic.title,
                unit_id=unit.id,
                unit_number=unit.unit_number,
                unit_title=unit.title,
                attempts=progress.attempts,
                correct=progress.correct_count,
                accuracy_percent=round(progress.score, 1),
            )
            for progress, topic, unit in self.session.execute(stmt)
        ]

    def _units_progress(self, user_id: int, *, unit_id: int | None = None) -> list[UnitProgress]:
        units_stmt = select(Unit).order_by(Unit.unit_number)
        if unit_id is not None:
            units_stmt = units_stmt.where(Unit.id == unit_id)
        units = self.session.scalars(units_stmt).all()

        practisable = defaultdict[int, int](int)  # unit id -> topics with gradable questions
        has_gradable = exists().where(PracticeQuestion.topic_id == Topic.id, gradable_clause())
        for unit_of_topic in self.session.scalars(select(Topic.unit_id).where(has_gradable)):
            practisable[unit_of_topic] += 1

        scores = defaultdict[int, list[float]](list)  # unit id -> scores of attempted topics
        progress_stmt = (
            select(Topic.unit_id, StudentProgress.score)
            .join(Topic, StudentProgress.topic_id == Topic.id)
            .where(StudentProgress.user_id == user_id, StudentProgress.attempts > 0)
        )
        for unit_of_topic, score in self.session.execute(progress_stmt):
            scores[unit_of_topic].append(score)

        result: list[UnitProgress] = []
        for unit in units:
            attempted = scores[unit.id]
            total = practisable[unit.id]
            result.append(
                UnitProgress(
                    unit_id=unit.id,
                    unit_number=unit.unit_number,
                    unit_title=unit.title,
                    topics_attempted=len(attempted),
                    topics_total=total,
                    avg_score=_percent(sum(attempted), 100 * len(attempted)),
                    progress_percent=_percent(sum(attempted), 100 * max(total, len(attempted))),
                )
            )
        return result
