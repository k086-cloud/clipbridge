import pytest

from clipbridge_server.auth import extract_bearer_token, token_matches


@pytest.mark.parametrize(
    ("header", "expected"),
    [
        (None, None),
        ("", None),
        ("Bearer abc", "abc"),
        ("bearer abc", "abc"),
        ("BEARER abc", "abc"),
        ("  Bearer   abc  ", "abc"),
        ("Bearer", None),
        ("Bearer ", None),
        ("Bearerabc", None),
        ("Basic abc", None),
        ("Token abc", None),
    ],
)
def test_extract_bearer_token(header, expected):
    assert extract_bearer_token(header) == expected


def test_token_matches_only_the_exact_value():
    assert token_matches("secret-token", "secret-token") is True
    assert token_matches("secret-token ", "secret-token") is False
    assert token_matches("SECRET-TOKEN", "secret-token") is False
    assert token_matches("", "secret-token") is False
    assert token_matches(None, "secret-token") is False
