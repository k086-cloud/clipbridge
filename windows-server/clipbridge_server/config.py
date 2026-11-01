"""Local configuration file holding the pairing token and server settings.

The file is created on first run next to this package (``windows-server/
config.json``) and is ignored by git because it contains the token.
"""

from __future__ import annotations

import json
import secrets
from dataclasses import asdict, dataclass, fields
from pathlib import Path

DEFAULT_CONFIG_PATH = Path(__file__).resolve().parents[1] / "config.json"
DEFAULT_HOST = "0.0.0.0"
DEFAULT_PORT = 8765
DEFAULT_POLL_INTERVAL_MS = 300
DEFAULT_MAX_TEXT_BYTES = 100 * 1024
DEFAULT_HISTORY_SIZE = 20

_INT_LIMITS = {
    "port": (1, 65535),
    "poll_interval_ms": (50, 60_000),
    "max_text_bytes": (1, 10 * 1024 * 1024),
    "history_size": (1, 1000),
}


class ConfigError(ValueError):
    """Raised when config.json cannot be used."""


@dataclass
class Config:
    token: str
    host: str = DEFAULT_HOST
    port: int = DEFAULT_PORT
    poll_interval_ms: int = DEFAULT_POLL_INTERVAL_MS
    max_text_bytes: int = DEFAULT_MAX_TEXT_BYTES
    history_size: int = DEFAULT_HISTORY_SIZE

    def validate(self) -> None:
        if not isinstance(self.token, str) or len(self.token) < 16:
            raise ConfigError("token must be a string of at least 16 characters")
        if not isinstance(self.host, str) or not self.host.strip():
            raise ConfigError("host must be a non-empty string")
        for name, (lower, upper) in _INT_LIMITS.items():
            value = getattr(self, name)
            if isinstance(value, bool) or not isinstance(value, int):
                raise ConfigError(f"{name} must be an integer")
            if not lower <= value <= upper:
                raise ConfigError(f"{name} must be between {lower} and {upper}")


def generate_token() -> str:
    """Return a new random pairing token (URL-safe, 43 characters)."""
    return secrets.token_urlsafe(32)


def save_config(config: Config, path: Path) -> None:
    config.validate()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(asdict(config), indent=2) + "\n", encoding="utf-8")


def load_config(path: Path) -> Config:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ConfigError(f"{path} is not valid JSON: {exc}") from exc
    if not isinstance(data, dict):
        raise ConfigError(f"{path} must contain a JSON object")
    known = {field.name for field in fields(Config)}
    unknown = sorted(set(data) - known)
    if unknown:
        raise ConfigError(f"{path} has unknown keys: {', '.join(unknown)}")
    if "token" not in data:
        raise ConfigError(f"{path} has no token; delete the file to generate a new one")
    config = Config(**data)
    config.validate()
    return config


def load_or_create_config(path: Path = DEFAULT_CONFIG_PATH) -> tuple[Config, bool]:
    """Load the config file, creating it with a fresh token when it is missing.

    Returns ``(config, created)``.
    """
    if path.exists():
        return load_config(path), False
    config = Config(token=generate_token())
    save_config(config, path)
    return config, True
