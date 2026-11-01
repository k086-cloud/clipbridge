"""HTTP API: health, latest item, history, and paste-from-phone.

No ``from __future__ import annotations`` here: FastAPI must evaluate the
``Annotated[..., Query(...)]`` hints, which reference closure variables.
"""

import time
from contextlib import asynccontextmanager
from typing import Annotated, AsyncIterator

from fastapi import Depends, FastAPI, HTTPException, Query, Request, status
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from . import __version__
from .auth import require_token
from .clipboard import ClipboardError, ClipboardMonitor, text_too_large
from .config import Config
from .history import ClipHistory, ClipItem


class ClipIn(BaseModel):
    content: str = Field(min_length=1, description="Plain text to put on the PC clipboard")


class ClipOut(BaseModel):
    id: str
    content: str
    timestamp: str
    source: str

    @classmethod
    def from_item(cls, item: ClipItem) -> "ClipOut":
        return cls(**item.to_dict())


class HistoryOut(BaseModel):
    items: list[ClipOut]


class HealthOut(BaseModel):
    status: str
    version: str
    history_items: int
    monitor_running: bool
    uptime_seconds: float


def create_app(
    config: Config,
    history: ClipHistory,
    monitor: ClipboardMonitor,
    *,
    start_monitor: bool = True,
) -> FastAPI:
    """Build the FastAPI app around an existing history and clipboard monitor."""

    @asynccontextmanager
    async def lifespan(_: FastAPI) -> AsyncIterator[None]:
        if start_monitor:
            monitor.start()
        try:
            yield
        finally:
            if start_monitor:
                monitor.stop()

    app = FastAPI(title="ClipBridge Windows Server", version=__version__, lifespan=lifespan)
    app.state.token = config.token
    app.state.started_at = time.monotonic()
    protected = [Depends(require_token)]
    max_items = history.max_items
    # JSON escaping can inflate the text (worst case \uXXXX per character).
    max_body_bytes = config.max_text_bytes * 6 + 4096

    @app.middleware("http")
    async def reject_oversized_bodies(request: Request, call_next):  # type: ignore[no-untyped-def]
        length = request.headers.get("content-length", "")
        if length.isdigit() and int(length) > max_body_bytes:
            return JSONResponse(
                status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                content={"detail": f"Request body exceeds {max_body_bytes} bytes."},
            )
        return await call_next(request)

    @app.get("/health", response_model=HealthOut)
    async def health() -> HealthOut:
        return HealthOut(
            status="ok",
            version=__version__,
            history_items=len(history),
            monitor_running=monitor.is_running,
            uptime_seconds=round(time.monotonic() - app.state.started_at, 1),
        )

    @app.get("/clip/latest", response_model=ClipOut, dependencies=protected)
    async def latest() -> ClipOut:
        item = history.latest()
        if item is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="No clipboard text recorded yet.",
            )
        return ClipOut.from_item(item)

    @app.get("/clip/history", response_model=HistoryOut, dependencies=protected)
    async def recent(
        limit: Annotated[int, Query(ge=1, le=max_items, description="Newest first")] = max_items,
    ) -> HistoryOut:
        return HistoryOut(items=[ClipOut.from_item(item) for item in history.recent(limit)])

    @app.post(
        "/clip",
        response_model=ClipOut,
        status_code=status.HTTP_201_CREATED,
        dependencies=protected,
    )
    def paste(body: ClipIn) -> ClipOut:
        if text_too_large(body.content, config.max_text_bytes):
            raise HTTPException(
                status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                detail=f"Text exceeds the {config.max_text_bytes} byte limit.",
            )
        try:
            item = monitor.set_clipboard(body.content)
        except ClipboardError as exc:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc)
            ) from exc
        return ClipOut.from_item(item)

    return app
