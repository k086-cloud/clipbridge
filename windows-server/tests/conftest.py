import pytest

from clipbridge_server.clipboard import ClipboardMonitor
from clipbridge_server.config import Config
from clipbridge_server.history import ClipHistory

TOKEN = "test-token-0123456789abcdef"


class FakeClipboard:
    """Stand-in for the Windows clipboard."""

    def __init__(self, text: str = "") -> None:
        self.text = text
        self.fail_reads = False
        self.fail_writes = False
        self.read_calls = 0
        self.writes: list[str] = []

    def read_text(self) -> str:
        self.read_calls += 1
        if self.fail_reads:
            raise RuntimeError("clipboard is busy")
        return self.text

    def write_text(self, text: str) -> None:
        if self.fail_writes:
            raise RuntimeError("clipboard is locked")
        self.text = text
        self.writes.append(text)


@pytest.fixture
def config() -> Config:
    return Config(token=TOKEN, max_text_bytes=1024, history_size=5)


@pytest.fixture
def history(config: Config) -> ClipHistory:
    return ClipHistory(config.history_size)


@pytest.fixture
def clipboard() -> FakeClipboard:
    return FakeClipboard()


@pytest.fixture
def monitor(clipboard: FakeClipboard, history: ClipHistory, config: Config) -> ClipboardMonitor:
    return ClipboardMonitor(
        clipboard, history, poll_interval=0.01, max_text_bytes=config.max_text_bytes
    )


@pytest.fixture
def auth() -> dict[str, str]:
    return {"Authorization": f"Bearer {TOKEN}"}
