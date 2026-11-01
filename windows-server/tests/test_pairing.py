import ipaddress
from urllib.parse import parse_qs, urlparse

from clipbridge_server.config import Config
from clipbridge_server.pairing import (
    lan_ip_candidates,
    pairing_banner,
    pairing_url,
    render_qr,
)


def test_lan_ip_candidates_are_ipv4_addresses():
    addresses = lan_ip_candidates()
    assert addresses
    for address in addresses:
        assert ipaddress.ip_address(address).version == 4
    assert len(addresses) == len(set(addresses))


def test_pairing_url_round_trips_its_fields():
    url = pairing_url("192.168.1.20", 8765, "tok/en+with=odd&chars")
    parsed = urlparse(url)
    assert parsed.scheme == "clipbridge"
    assert parsed.netloc == "pair"
    query = parse_qs(parsed.query)
    assert query == {"host": ["192.168.1.20"], "port": ["8765"], "token": ["tok/en+with=odd&chars"]}


def test_render_qr_produces_a_square_block_of_lines():
    rendered = render_qr("clipbridge://pair?host=1.2.3.4&port=8765&token=abc")
    lines = [line for line in rendered.splitlines() if line.strip()]
    assert len(lines) > 10
    assert len({len(line) for line in lines}) == 1


def test_banner_lists_everything_needed_to_pair():
    config = Config(token="banner-token-0123456789", port=9999)
    banner = pairing_banner(config, ["10.0.0.5", "192.168.56.1"], show_qr=False)
    assert "10.0.0.5" in banner
    assert "192.168.56.1" in banner
    assert "9999" in banner
    assert "banner-token-0123456789" in banner
    assert "http://10.0.0.5:9999/health" in banner
    assert "clipbridge://pair?" in banner
    with_qr = pairing_banner(config, ["10.0.0.5"], show_qr=True)
    assert len(with_qr.splitlines()) > len(banner.splitlines()) + 10
