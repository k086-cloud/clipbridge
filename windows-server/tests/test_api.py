import pytest
from fastapi.testclient import TestClient

from clipbridge_server import __version__
from clipbridge_server.api import create_app


@pytest.fixture
def app(config, history, monitor):
    return create_app(config, history, monitor, start_monitor=False)


@pytest.fixture
def client(app):
    with TestClient(app) as test_client:
        yield test_client


# --- health -----------------------------------------------------------------


def test_health_needs_no_token(client):
    response = client.get("/health")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert body["version"] == __version__
    assert body["history_items"] == 0
    assert body["monitor_running"] is False
    assert body["uptime_seconds"] >= 0


def test_json_responses_declare_utf8(client, auth, history):
    history.add("中文 and ümlauts", "pc")
    for path in ("/health", "/clip/latest", "/clip/history"):
        response = client.get(path, headers=auth)
        assert response.status_code == 200
        assert response.headers["content-type"] == "application/json; charset=utf-8"
    assert client.get("/clip/latest", headers=auth).json()["content"] == "中文 and ümlauts"


# --- authentication ---------------------------------------------------------


@pytest.mark.parametrize("path", ["/clip/latest", "/clip/history"])
def test_get_routes_require_token(client, path):
    response = client.get(path)
    assert response.status_code == 401
    assert response.headers["WWW-Authenticate"] == "Bearer"
    assert response.json() == {"detail": "Missing or invalid bearer token."}


def test_post_requires_token(client, clipboard):
    response = client.post("/clip", json={"content": "hi"})
    assert response.status_code == 401
    assert clipboard.writes == []


@pytest.mark.parametrize(
    "headers",
    [
        {"Authorization": "Bearer wrong-token"},
        {"Authorization": "Basic dGVzdA=="},
        {"Authorization": "Bearer"},
    ],
)
def test_wrong_credentials_are_rejected(client, headers):
    assert client.get("/clip/latest", headers=headers).status_code == 401


def test_correct_token_is_accepted(client, auth):
    assert client.get("/clip/history", headers=auth).status_code == 200


# --- latest / history -------------------------------------------------------


def test_latest_is_404_when_history_is_empty(client, auth):
    response = client.get("/clip/latest", headers=auth)
    assert response.status_code == 404
    assert response.json()["detail"] == "No clipboard text recorded yet."


def test_latest_returns_newest_item(client, auth, history):
    history.add("older", "pc")
    newest = history.add("newest", "phone")
    response = client.get("/clip/latest", headers=auth)
    assert response.status_code == 200
    assert response.json() == {
        "id": newest.id,
        "content": "newest",
        "timestamp": newest.timestamp.isoformat(timespec="milliseconds"),
        "source": "phone",
    }


def test_history_is_newest_first_with_limit(client, auth, history):
    for index in range(4):
        history.add(f"item {index}", "pc")
    response = client.get("/clip/history", headers=auth)
    assert [item["content"] for item in response.json()["items"]] == [
        "item 3",
        "item 2",
        "item 1",
        "item 0",
    ]
    limited = client.get("/clip/history", params={"limit": 2}, headers=auth)
    assert [item["content"] for item in limited.json()["items"]] == ["item 3", "item 2"]


@pytest.mark.parametrize("limit", [0, -1, 6, "many"])
def test_history_limit_is_validated(client, auth, limit):
    response = client.get("/clip/history", params={"limit": limit}, headers=auth)
    assert response.status_code == 422


# --- paste from phone -------------------------------------------------------


def test_post_writes_clipboard_and_records_phone_item(client, auth, clipboard, history, monitor):
    response = client.post("/clip", json={"content": "sent from iPhone"}, headers=auth)
    assert response.status_code == 201
    body = response.json()
    assert body["content"] == "sent from iPhone"
    assert body["source"] == "phone"
    assert clipboard.text == "sent from iPhone"
    assert history.latest().id == body["id"]

    # The monitor must not record the same text again as a pc item.
    assert monitor.poll_once() is None
    assert [item.source for item in history.recent()] == ["phone"]

    latest = client.get("/clip/latest", headers=auth)
    assert latest.json()["id"] == body["id"]


def test_post_keeps_newlines_and_unicode(client, auth, clipboard):
    text = "第一行\r\n第二行\n🙂"
    response = client.post("/clip", json={"content": text}, headers=auth)
    assert response.status_code == 201
    assert clipboard.text == text


@pytest.mark.parametrize("payload", [{"content": ""}, {}, {"text": "x"}, {"content": 5}])
def test_post_validates_payload(client, auth, payload, clipboard):
    response = client.post("/clip", json=payload, headers=auth)
    assert response.status_code == 422
    assert clipboard.writes == []


def test_post_rejects_text_over_limit(client, auth, clipboard, config):
    response = client.post("/clip", json={"content": "x" * (config.max_text_bytes + 1)}, headers=auth)
    assert response.status_code == 413
    assert clipboard.writes == []


def test_post_accepts_text_at_limit(client, auth, clipboard, config):
    response = client.post("/clip", json={"content": "x" * config.max_text_bytes}, headers=auth)
    assert response.status_code == 201
    assert len(clipboard.writes) == 1


def test_huge_request_body_is_rejected_early(client, auth, clipboard, config):
    oversized = "x" * (config.max_text_bytes * 6 + 5000)
    response = client.post("/clip", json={"content": oversized}, headers=auth)
    assert response.status_code == 413
    assert "Request body exceeds" in response.json()["detail"]
    assert clipboard.writes == []


def test_post_reports_clipboard_write_failure(client, auth, clipboard, history):
    clipboard.fail_writes = True
    response = client.post("/clip", json={"content": "x"}, headers=auth)
    assert response.status_code == 503
    assert "clipboard" in response.json()["detail"].lower()
    assert len(history) == 0
