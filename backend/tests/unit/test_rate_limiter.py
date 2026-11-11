import logging

import pytest

from app.services.ai.errors import AIQuotaExceededError
from app.services.ai.rate_limiter import DAY, MINUTE, RateLimiter


class FakeClock:
    def __init__(self) -> None:
        self.now = 1000.0

    def __call__(self) -> float:
        return self.now


def test_allows_up_to_limit_then_raises_with_retry_after() -> None:
    clock = FakeClock()
    limiter = RateLimiter(per_minute=3, per_day=100, clock=clock)
    for _ in range(3):
        limiter.acquire()
    clock.now += 20
    with pytest.raises(AIQuotaExceededError) as info:
        limiter.acquire()
    assert info.value.retry_after_seconds == 40
    assert info.value.headers == {"Retry-After": "40"}


def test_minute_window_slides() -> None:
    clock = FakeClock()
    limiter = RateLimiter(per_minute=2, per_day=100, clock=clock)
    limiter.acquire()
    limiter.acquire()
    clock.now += MINUTE
    limiter.acquire()  # oldest calls expired
    assert limiter.usage() == {60: 1, 86400: 3}


def test_daily_limit_enforced_across_minutes() -> None:
    clock = FakeClock()
    limiter = RateLimiter(per_minute=100, per_day=2, clock=clock)
    limiter.acquire()
    clock.now += 3600
    limiter.acquire()
    clock.now += 3600
    with pytest.raises(AIQuotaExceededError) as info:
        limiter.acquire()
    assert info.value.retry_after_seconds == int(DAY - 7200)
    clock.now += DAY
    limiter.acquire()


def test_rejected_call_is_not_counted() -> None:
    clock = FakeClock()
    limiter = RateLimiter(per_minute=1, per_day=100, clock=clock)
    limiter.acquire()
    with pytest.raises(AIQuotaExceededError):
        limiter.acquire()
    assert limiter.usage()[60] == 1


def test_warns_when_close_to_limit(caplog: pytest.LogCaptureFixture) -> None:
    limiter = RateLimiter(per_minute=10, per_day=1000, clock=FakeClock())
    with caplog.at_level(logging.WARNING):
        for _ in range(7):
            limiter.acquire()
        assert "close to the free-tier limit" not in caplog.text
        limiter.acquire()  # 8/10 = 80 %
    assert "close to the free-tier limit: 8/10 requests per 60s" in caplog.text


def test_logs_when_limit_reached(caplog: pytest.LogCaptureFixture) -> None:
    limiter = RateLimiter(per_minute=1, per_day=10, clock=FakeClock())
    limiter.acquire()
    with caplog.at_level(logging.WARNING), pytest.raises(AIQuotaExceededError):
        limiter.acquire()
    assert "rate limit reached" in caplog.text
