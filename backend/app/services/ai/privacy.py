"""Remove personal contact data from free text before it leaves the server.

The prompt itself is built from ``TutorPrompt``, which has no personal fields; this scrubber
covers what a student might *type* into a question (email, phone, CNIC).
"""

import re
from typing import Final

REDACTED: Final = "[redacted]"

_PATTERNS: Final = (
    re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"),  # email
    re.compile(r"\b\d{5}-\d{7}-\d\b|\b\d{13}\b"),  # CNIC (with or without dashes)
    re.compile(r"(?:\+92|0092|\b0)[\s-]?3\d{2}[\s-]?\d{7}\b"),  # Pakistani mobile number
)


def scrub_pii(text: str) -> str:
    for pattern in _PATTERNS:
        text = pattern.sub(REDACTED, text)
    return text
