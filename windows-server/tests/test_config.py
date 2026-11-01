import json

import pytest

from clipbridge_server.config import (
    DEFAULT_PORT,
    Config,
    ConfigError,
    generate_token,
    load_config,
    load_or_create_config,
)


def test_first_run_creates_file_with_random_token(tmp_path):
    path = tmp_path / "config.json"
    config, created = load_or_create_config(path)
    assert created is True
    assert path.exists()
    assert config.port == DEFAULT_PORT
    assert len(config.token) >= 32

    data = json.loads(path.read_text(encoding="utf-8"))
    assert data["token"] == config.token
    assert data["port"] == DEFAULT_PORT


def test_second_run_reuses_the_same_token(tmp_path):
    path = tmp_path / "config.json"
    first, _ = load_or_create_config(path)
    second, created = load_or_create_config(path)
    assert created is False
    assert second.token == first.token


def test_tokens_are_random():
    assert generate_token() != generate_token()


def test_custom_values_are_loaded(tmp_path):
    path = tmp_path / "config.json"
    path.write_text(
        json.dumps({"token": "x" * 20, "port": 9000, "history_size": 3}), encoding="utf-8"
    )
    config = load_config(path)
    assert config.port == 9000
    assert config.history_size == 3
    assert config.poll_interval_ms == 300


@pytest.mark.parametrize(
    "data",
    [
        {"port": 8765},
        {"token": "short"},
        {"token": "x" * 20, "port": 70000},
        {"token": "x" * 20, "port": "8765"},
        {"token": "x" * 20, "history_size": 0},
        {"token": "x" * 20, "poll_interval_ms": 1},
        {"token": "x" * 20, "unexpected": 1},
    ],
)
def test_invalid_config_is_reported(tmp_path, data):
    path = tmp_path / "config.json"
    path.write_text(json.dumps(data), encoding="utf-8")
    with pytest.raises(ConfigError):
        load_config(path)


def test_invalid_json_is_reported(tmp_path):
    path = tmp_path / "config.json"
    path.write_text("{not json", encoding="utf-8")
    with pytest.raises(ConfigError):
        load_config(path)


def test_validate_rejects_bool_port():
    with pytest.raises(ConfigError):
        Config(token="x" * 20, port=True).validate()
