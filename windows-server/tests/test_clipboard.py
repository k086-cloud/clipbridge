import time

import pytest

from clipbridge_server.clipboard import ClipboardError, ClipboardMonitor, text_too_large


def test_first_poll_records_current_clipboard_as_pc(monitor, clipboard, history):
    clipboard.text = "already there"
    item = monitor.poll_once()
    assert item is not None
    assert item.source == "pc"
    assert history.latest().content == "already there"


def test_unchanged_clipboard_is_not_recorded_again(monitor, clipboard, history):
    clipboard.text = "same"
    monitor.poll_once()
    for _ in range(5):
        assert monitor.poll_once() is None
    assert len(history) == 1


def test_phone_text_is_written_but_not_echoed_as_pc(monitor, clipboard, history):
    clipboard.text = "from the pc"
    monitor.poll_once()

    item = monitor.set_clipboard("from the phone")
    assert clipboard.text == "from the phone"
    assert item.source == "phone"

    for _ in range(5):
        assert monitor.poll_once() is None
    sources = [entry.source for entry in history.recent()]
    assert sources == ["phone", "pc"]


def test_user_copy_after_phone_paste_is_recorded(monitor, clipboard, history):
    monitor.set_clipboard("from the phone")
    clipboard.text = "typed on the pc later"
    item = monitor.poll_once()
    assert item is not None and item.source == "pc"
    assert [entry.content for entry in history.recent()] == [
        "typed on the pc later",
        "from the phone",
    ]


def test_phone_text_equal_to_current_clipboard_is_not_duplicated_as_pc(
    monitor, clipboard, history
):
    clipboard.text = "shared"
    monitor.poll_once()
    monitor.set_clipboard("shared")
    assert monitor.poll_once() is None
    assert [entry.source for entry in history.recent()] == ["phone", "pc"]


def test_empty_clipboard_is_ignored(monitor, clipboard, history):
    clipboard.text = ""
    assert monitor.poll_once() is None
    assert len(history) == 0


def test_oversized_text_is_ignored_but_remembered(monitor, clipboard, history, config):
    clipboard.text = "x" * (config.max_text_bytes + 1)
    assert monitor.poll_once() is None
    assert len(history) == 0
    # The same oversized text is not re-evaluated on every poll.
    reads_before = clipboard.read_calls
    assert monitor.poll_once() is None
    assert clipboard.read_calls == reads_before + 1
    clipboard.text = "small again"
    assert monitor.poll_once() is not None


def test_text_too_large_counts_utf8_bytes():
    assert text_too_large("é" * 10, 19) is True
    assert text_too_large("é" * 10, 20) is False


def test_read_failures_are_swallowed(monitor, clipboard, history):
    clipboard.fail_reads = True
    assert monitor.poll_once() is None
    clipboard.fail_reads = False
    clipboard.text = "recovered"
    assert monitor.poll_once().content == "recovered"


def test_write_failure_raises_clipboard_error(monitor, clipboard, history):
    clipboard.fail_writes = True
    with pytest.raises(ClipboardError):
        monitor.set_clipboard("will fail")
    assert len(history) == 0


def test_background_thread_records_changes(monitor, clipboard, history):
    clipboard.text = "initial"
    monitor.start()
    try:
        assert monitor.is_running
        deadline = time.time() + 2
        while len(history) < 1 and time.time() < deadline:
            time.sleep(0.01)
        clipboard.text = "changed while running"
        deadline = time.time() + 2
        while len(history) < 2 and time.time() < deadline:
            time.sleep(0.01)
    finally:
        monitor.stop()
    assert not monitor.is_running
    assert [entry.content for entry in history.recent()] == ["changed while running", "initial"]


def test_invalid_monitor_settings_are_rejected(clipboard, history):
    with pytest.raises(ValueError):
        ClipboardMonitor(clipboard, history, poll_interval=0)
    with pytest.raises(ValueError):
        ClipboardMonitor(clipboard, history, max_text_bytes=0)
