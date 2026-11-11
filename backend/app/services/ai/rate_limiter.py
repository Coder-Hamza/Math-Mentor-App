"""In-process sliding-window limiter that keeps Gemini usage inside the free tier.

Rejecting locally (429 with Retry-After) is friendlier and cheaper than letting Google
reject us. Warns in the log when usage crosses ``warn_ratio`` of either limit.

Note: state is per process. With several uvicorn workers, divide the limits accordingly.
"""

import logging
import math
import time
from collections import deque
from collections.abc import Callable

from app.services.ai.errors import AIQuotaExceededError

logger = logging.getLogger(__name__)

MINUTE = 60.0
DAY = 86_400.0


class RateLimiter:
    def __init__(
        self,
        per_minute: int,
        per_day: int,
        *,
        warn_ratio: float = 0.8,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self._windows = ((MINUTE, per_minute, deque[float]()), (DAY, per_day, deque[float]()))
        self._warn_ratio = warn_ratio
        self._clock = clock

    def acquire(self) -> None:
        """Record one request, or raise ``AIQuotaExceededError`` if a window is full."""
        now = self._clock()
        for span, limit, calls in self._windows:
            while calls and now - calls[0] >= span:
                calls.popleft()
            if len(calls) >= limit:
                retry_after = max(1, math.ceil(span - (now - calls[0])))
                logger.warning(
                    "Gemini local rate limit reached: %d/%d requests per %ds window",
                    len(calls),
                    limit,
                    int(span),
                )
                raise AIQuotaExceededError(retry_after)
        for span, limit, calls in self._windows:
            calls.append(now)
            if len(calls) >= self._warn_ratio * limit:
                logger.warning(
                    "Gemini usage is close to the free-tier limit: %d/%d requests per %ds",
                    len(calls),
                    limit,
                    int(span),
                )

    def usage(self) -> dict[int, int]:
        """Requests currently counted per window length (seconds)."""
        now = self._clock()
        return {
            int(span): sum(1 for t in calls if now - t < span) for span, _, calls in self._windows
        }
