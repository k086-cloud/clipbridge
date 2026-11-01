"""Clipboard access plus the polling monitor that feeds the history."""

from __future__ import annotations

import logging
import threading
from typing import Protocol

from .history import ClipHistory, ClipItem

log = logging.getLogger(__name__)

DEFAULT_POLL_INTERVAL = 0.3
DEFAULT_MAX_TEXT_BYTES = 100 * 1024


class ClipboardBackend(Protocol):
    def read_text(self) -> str: ...

    def write_text(self, text: str) -> None: ...


class PyperclipBackend:
    """Real clipboard access through pyperclip (ctypes Win32 calls on Windows)."""

    def __init__(self) -> None:
        import pyperclip  # imported here so tests never touch the real clipboard

        self._pyperclip = pyperclip

    def read_text(self) -> str:
        return self._pyperclip.paste() or ""

    def write_text(self, text: str) -> None:
        self._pyperclip.copy(text)


class ClipboardError(RuntimeError):
    """Raised when the clipboard cannot be written."""


def text_too_large(text: str, max_bytes: int) -> bool:
    return len(text.encode("utf-8")) > max_bytes


class ClipboardMonitor:
    """Poll the clipboard and record new text, without echoing phone pastes.

    ``_last_seen`` is the clipboard content the monitor already knows about.
    A phone paste writes the clipboard and updates ``_last_seen`` under the
    same lock that the poll uses to read and compare, so the next poll sees
    "no change" and the text is never recorded a second time as a pc item.
    """

    def __init__(
        self,
        backend: ClipboardBackend,
        history: ClipHistory,
        *,
        poll_interval: float = DEFAULT_POLL_INTERVAL,
        max_text_bytes: int = DEFAULT_MAX_TEXT_BYTES,
    ) -> None:
        if poll_interval <= 0:
            raise ValueError("poll_interval must be positive")
        if max_text_bytes < 1:
            raise ValueError("max_text_bytes must be at least 1")
        self._backend = backend
        self._history = history
        self._poll_interval = poll_interval
        self._max_text_bytes = max_text_bytes
        self._lock = threading.Lock()
        self._last_seen: str | None = None
        self._stop_event = threading.Event()
        self._thread: threading.Thread | None = None
        self._read_failures = 0

    @property
    def is_running(self) -> bool:
        return self._thread is not None and self._thread.is_alive()

    def poll_once(self) -> ClipItem | None:
        """Check the clipboard once and return the item recorded, if any."""
        try:
            with self._lock:
                content = self._backend.read_text()
                if content == self._last_seen:
                    return None
                self._last_seen = content
        except Exception as exc:  # another app holds the clipboard, etc.
            self._read_failures += 1
            if self._read_failures <= 3 or self._read_failures % 100 == 0:
                log.warning("Clipboard read failed (%d so far): %s", self._read_failures, exc)
            return None
        self._read_failures = 0

        if not content:
            return None
        if text_too_large(content, self._max_text_bytes):
            log.info(
                "Ignored clipboard text of %d bytes (limit %d)",
                len(content.encode("utf-8")),
                self._max_text_bytes,
            )
            return None
        item = self._history.add(content, "pc")
        log.info("Recorded clipboard text from pc (%d chars)", len(content))
        log.debug("pc clipboard preview: %r", content[:60])
        return item

    def set_clipboard(self, text: str, source: str = "phone") -> ClipItem:
        """Put text from the phone on the clipboard and record it in the history."""
        with self._lock:
            try:
                self._backend.write_text(text)
            except Exception as exc:
                raise ClipboardError(f"Could not write to the clipboard: {exc}") from exc
            self._last_seen = text
        item = self._history.add(text, source)
        log.info("Wrote clipboard text from %s (%d chars)", source, len(text))
        return item

    def start(self) -> None:
        if self.is_running:
            return
        self._stop_event.clear()
        self._thread = threading.Thread(target=self._run, name="clipboard-monitor", daemon=True)
        self._thread.start()
        log.info("Clipboard monitor started (every %d ms)", round(self._poll_interval * 1000))

    def stop(self, timeout: float = 2.0) -> None:
        if self._thread is None:
            return
        self._stop_event.set()
        self._thread.join(timeout)
        self._thread = None
        log.info("Clipboard monitor stopped")

    def _run(self) -> None:
        self.poll_once()
        while not self._stop_event.wait(self._poll_interval):
            self.poll_once()
