import json
from datetime import datetime

import pytest

from clipbridge_server.history import ClipHistory


def test_add_returns_item_with_all_fields():
    history = ClipHistory()
    item = history.add("hello", "pc")
    assert item.content == "hello"
    assert item.source == "pc"
    assert len(item.id) == 32
    assert isinstance(item.timestamp, datetime)
    assert item.timestamp.tzinfo is not None


def test_latest_is_none_when_empty():
    assert ClipHistory().latest() is None
    assert len(ClipHistory()) == 0


def test_latest_returns_most_recent_item():
    history = ClipHistory()
    history.add("first", "pc")
    second = history.add("second", "phone")
    assert history.latest() == second


def test_recent_is_newest_first_and_respects_limit():
    history = ClipHistory()
    for index in range(4):
        history.add(f"item {index}", "pc")
    contents = [item.content for item in history.recent()]
    assert contents == ["item 3", "item 2", "item 1", "item 0"]
    assert [item.content for item in history.recent(2)] == ["item 3", "item 2"]
    assert len(history.recent(10)) == 4


def test_oldest_items_are_dropped_beyond_max_items():
    history = ClipHistory(max_items=3)
    for index in range(5):
        history.add(f"item {index}", "pc")
    assert len(history) == 3
    assert [item.content for item in history.recent()] == ["item 4", "item 3", "item 2"]


def test_default_capacity_is_twenty():
    history = ClipHistory()
    assert history.max_items == 20
    for index in range(25):
        history.add(str(index), "pc")
    assert len(history) == 20
    assert history.recent()[-1].content == "5"


def test_ids_are_unique():
    history = ClipHistory()
    ids = {history.add("same text", "pc").id for _ in range(50)}
    assert len(ids) == 50


def test_invalid_source_is_rejected():
    history = ClipHistory()
    with pytest.raises(ValueError):
        history.add("x", "tablet")
    assert len(history) == 0


def test_invalid_limits_are_rejected():
    with pytest.raises(ValueError):
        ClipHistory(max_items=0)
    with pytest.raises(ValueError):
        ClipHistory().recent(0)


def test_to_dict_is_json_serialisable():
    item = ClipHistory().add("text", "phone")
    data = json.loads(json.dumps(item.to_dict()))
    assert data["id"] == item.id
    assert data["content"] == "text"
    assert data["source"] == "phone"
    assert datetime.fromisoformat(data["timestamp"]) == item.timestamp.replace(
        microsecond=(item.timestamp.microsecond // 1000) * 1000
    )


def test_clear_empties_history_and_reports_count():
    history = ClipHistory(max_items=3)
    for index in range(2):
        history.add(f"item {index}", "pc")
    assert history.clear() == 2
    assert len(history) == 0
    assert history.latest() is None
    assert history.recent() == []
    assert history.clear() == 0


def test_clear_keeps_capacity():
    history = ClipHistory(max_items=3)
    history.add("before", "pc")
    history.clear()
    assert history.max_items == 3
    for index in range(5):
        history.add(f"item {index}", "phone")
    assert [item.content for item in history.recent()] == ["item 4", "item 3", "item 2"]
