"""Bearer-token authentication shared by every protected route."""

from __future__ import annotations

import secrets

from fastapi import HTTPException, Request, status


def extract_bearer_token(authorization: str | None) -> str | None:
    """Return the token from an ``Authorization: Bearer <token>`` header value."""
    if not authorization:
        return None
    scheme, _, value = authorization.strip().partition(" ")
    value = value.strip()
    if scheme.lower() != "bearer" or not value:
        return None
    return value


def token_matches(presented: str | None, expected: str) -> bool:
    """Constant-time comparison so timing does not leak the token."""
    if presented is None:
        return False
    return secrets.compare_digest(presented.encode("utf-8"), expected.encode("utf-8"))


async def require_token(request: Request) -> None:
    """FastAPI dependency: reject requests that do not carry the configured token."""
    presented = extract_bearer_token(request.headers.get("authorization"))
    if not token_matches(presented, request.app.state.token):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing or invalid bearer token.",
            headers={"WWW-Authenticate": "Bearer"},
        )
