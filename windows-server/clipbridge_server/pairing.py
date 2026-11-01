"""Pairing information: LAN address, pairing URL and a terminal QR code."""

from __future__ import annotations

import io
import socket
from urllib.parse import urlencode

from .config import Config

PAIRING_SCHEME = "clipbridge"


def lan_ip_candidates() -> list[str]:
    """Best-guess IPv4 addresses of this machine on the local network.

    The first entry is the address of the interface that owns the default
    route (found with a UDP socket that never sends anything); the rest come
    from the hostname lookup.
    """
    candidates: list[str] = []
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
            probe.connect(("192.0.2.1", 9))  # TEST-NET address; no packet is sent
            candidates.append(probe.getsockname()[0])
    except OSError:
        pass
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            address = info[4][0]
            if address not in candidates and not address.startswith("127."):
                candidates.append(address)
    except OSError:
        pass
    return candidates or ["127.0.0.1"]


def pairing_url(host: str, port: int, token: str) -> str:
    """URL the iOS app will read from the QR code."""
    return f"{PAIRING_SCHEME}://pair?" + urlencode({"host": host, "port": port, "token": token})


def render_qr(data: str, *, invert: bool = True) -> str:
    """Render ``data`` as a QR code made of half-block characters."""
    import qrcode

    qr = qrcode.QRCode(border=1)
    qr.add_data(data)
    qr.make(fit=True)
    buffer = io.StringIO()
    qr.print_ascii(out=buffer, invert=invert)
    return buffer.getvalue()


def pairing_banner(config: Config, addresses: list[str], *, show_qr: bool = True) -> str:
    """Text block printed at startup with everything needed to pair."""
    primary = addresses[0]
    url = pairing_url(primary, config.port, config.token)
    others = f"  (also: {', '.join(addresses[1:])})" if len(addresses) > 1 else ""
    lines = [
        "",
        "=" * 64,
        "ClipBridge Windows server",
        "=" * 64,
        f"LAN address : {primary}{others}",
        f"Port        : {config.port}",
        f"Token       : {config.token}",
        f"Health URL  : http://{primary}:{config.port}/health",
        f"Pairing URL : {url}",
        "",
    ]
    if show_qr:
        lines.append("Scan this with the ClipBridge iOS app to pair:")
        lines.append(render_qr(url))
    lines.append("=" * 64)
    return "\n".join(lines)
