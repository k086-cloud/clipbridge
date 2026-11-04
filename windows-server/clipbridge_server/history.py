"""In-memory history of clipboard items."""

from __future__ import annotations

import threading
import uuid
from collections import deque
from dataclasses import dataclass
from datetime import datetime, timezone

SOURCES: tuple[str, ...] = ("pc", "phone")
DEFAULT_MAX_ITEMS = 20


@dataclass(frozen=True)
class ClipItem:
    """One clipboard entry. ``source`` is "pc" or "phone"."""

    id: str
    content: str
    timestamp: datetime
    source: str

    def to_dict(self) -> dict[str, str]:
        return {
            "id": self.id,
            "content": self.content,
            "timestamp": self.timestamp.isoformat(timespec="milliseconds"),
            "source": self.source,
        }


class ClipHistory:
    """Thread-safe ring buffer that keeps only the most recent items."""

    def __init__(self, max_items: int = DEFAULT_MAX_ITEMS) -> None:
        if max_items < 1:
            raise ValueError("max_items must be at least 1")
        self._items: deque[ClipItem] = deque(maxlen=max_items)
        self._lock = threading.Lock()

    @property
    def max_items(self) -> int:
        return self._items.maxlen or DEFAULT_MAX_ITEMS

    def add(self, content: str, source: str) -> ClipItem:
        """Append an item; the oldest one is dropped once the buffer is full."""
        if source not in SOURCES:
            raise ValueError(f"source must be one of {SOURCES}, got {source!r}")
        item = ClipItem(
            id=uuid.uuid4().hex,
            content=content,
            timestamp=datetime.now(timezone.utc).astimezone(),
            source=source,
        )
        with self._lock:
            self._items.append(item)
        return item

    def latest(self) -> ClipItem | None:
        with self._lock:
            return self._items[-1] if self._items else None

    def recent(self, limit: int | None = None) -> list[ClipItem]:
        """Return items newest first, at most ``limit`` of them."""
        if limit is not None and limit < 1:
            raise ValueError("limit must be at least 1")
        with self._lock:
            items = list(reversed(self._items))
        return items if limit is None else items[:limit]

    def clear(self) -> int:
        """Drop every item and return how many there were. The size limit is kept."""
        with self._lock:
            count = len(self._items)
            self._items.clear()
        return count

    def __len__(self) -> int:
        with self._lock:
            return len(self._items)
