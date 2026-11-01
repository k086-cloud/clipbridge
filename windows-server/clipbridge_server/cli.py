"""Command-line entry point: ``python -m clipbridge_server``."""

from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path

from .api import create_app
from .clipboard import ClipboardMonitor, PyperclipBackend
from .config import DEFAULT_CONFIG_PATH, ConfigError, load_or_create_config
from .history import ClipHistory
from .pairing import lan_ip_candidates, pairing_banner

log = logging.getLogger("clipbridge")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="python -m clipbridge_server",
        description="ClipBridge clipboard sync server (Windows side).",
    )
    parser.add_argument(
        "--config",
        type=Path,
        default=DEFAULT_CONFIG_PATH,
        help=f"path of the config file (default: {DEFAULT_CONFIG_PATH})",
    )
    parser.add_argument("--host", help="bind address, overrides config.json for this run")
    parser.add_argument("--port", type=int, help="port, overrides config.json for this run")
    parser.add_argument("--no-qr", action="store_true", help="do not print the pairing QR code")
    parser.add_argument(
        "--log-level",
        default="INFO",
        choices=["DEBUG", "INFO", "WARNING", "ERROR"],
        help="log verbosity (default: INFO)",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    _use_utf8_console()
    logging.basicConfig(
        level=args.log_level,
        format="%(asctime)s %(levelname)-7s %(name)s: %(message)s",
        datefmt="%H:%M:%S",
    )

    try:
        config, created = load_or_create_config(args.config)
    except ConfigError as exc:
        log.error("Cannot use %s: %s", args.config, exc)
        return 2
    if created:
        log.info("Created %s with a new pairing token", args.config)
    if args.host:
        config.host = args.host
    if args.port:
        config.port = args.port

    history = ClipHistory(config.history_size)
    monitor = ClipboardMonitor(
        PyperclipBackend(),
        history,
        poll_interval=config.poll_interval_ms / 1000,
        max_text_bytes=config.max_text_bytes,
    )
    app = create_app(config, history, monitor)

    addresses = lan_ip_candidates()
    try:
        banner = pairing_banner(config, addresses, show_qr=not args.no_qr)
    except Exception as exc:  # QR rendering problems must not stop the server
        log.warning("Could not render the QR code: %s", exc)
        banner = pairing_banner(config, addresses, show_qr=False)
    print(banner, flush=True)

    import uvicorn

    uvicorn.run(
        app,
        host=config.host,
        port=config.port,
        log_config=None,
        log_level=args.log_level.lower(),
    )
    return 0


def _use_utf8_console() -> None:
    """Make the QR code's block characters printable on a GBK/CP936 console."""
    for stream in (sys.stdout, sys.stderr):
        reconfigure = getattr(stream, "reconfigure", None)
        if reconfigure is None:
            continue
        try:
            reconfigure(encoding="utf-8", errors="replace")
        except (ValueError, OSError):
            pass
