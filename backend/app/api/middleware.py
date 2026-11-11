"""Request logging: method, path, status and duration for every request.

Only the path is logged — never the query string, headers or body (tokens, passwords and
questions stay out of the logs).
"""

import logging
import time
from collections.abc import Awaitable, Callable

from fastapi import Request, Response

logger = logging.getLogger("app.request")


async def log_requests(
    request: Request, call_next: Callable[[Request], Awaitable[Response]]
) -> Response:
    start = time.perf_counter()
    try:
        response = await call_next(request)
    except Exception:
        elapsed_ms = (time.perf_counter() - start) * 1000
        logger.info("%s %s -> 500 (%.0f ms)", request.method, request.url.path, elapsed_ms)
        raise
    elapsed_ms = (time.perf_counter() - start) * 1000
    logger.info(
        "%s %s -> %d (%.0f ms)",
        request.method,
        request.url.path,
        response.status_code,
        elapsed_ms,
    )
    return response
