"""Conforming sample: passes the strict Ruff base config."""

from datetime import datetime, timezone
from pathlib import Path


def read_first_line(path: Path) -> str:
    """Return the first stripped line of a UTF-8 text file."""
    with path.open(encoding="utf-8") as handle:
        return handle.readline().strip()


def now_utc() -> datetime:
    """Return the current timezone-aware UTC timestamp."""
    return datetime.now(tz=timezone.utc)
