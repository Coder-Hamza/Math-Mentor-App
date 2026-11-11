"""Wire ``LOG_LEVEL`` to Python logging for the application's own loggers (``app.*``).

Uvicorn configures only its own loggers, so without this the app's INFO logs (e.g. which
Gemini model answered) are dropped. A single handler is attached to the ``app`` logger;
records still propagate, so pytest's ``caplog`` keeps working. Safe to call repeatedly.
"""

import logging
import sys
from typing import Final

APP_LOGGER: Final = "app"
LOG_FORMAT: Final = "%(asctime)s %(levelname)-7s %(name)s: %(message)s"
_HANDLER_NAME: Final = "mathmentor-app-handler"


def configure_logging(level: str) -> logging.Logger:
    logger = logging.getLogger(APP_LOGGER)
    logger.setLevel(level)
    if not any(h.get_name() == _HANDLER_NAME for h in logger.handlers):
        handler = logging.StreamHandler(sys.stderr)
        handler.set_name(_HANDLER_NAME)
        handler.setFormatter(logging.Formatter(LOG_FORMAT))
        logger.addHandler(handler)
    return logger
