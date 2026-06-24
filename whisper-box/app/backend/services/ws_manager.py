"""
ws_manager.py — WebSocket connection manager.

- Supports multiple connections per job_id
- Silently handles WebSocketDisconnect
- Thread-safe for asyncio context
"""

import json
import logging
from collections import defaultdict
from typing import Any

from fastapi import WebSocket
from starlette.websockets import WebSocketState

logger = logging.getLogger(__name__)


class ConnectionManager:
    def __init__(self):
        # job_id → list of active WebSocket connections
        self._connections: dict[int, list[WebSocket]] = defaultdict(list)

    def connect(self, job_id: int, ws: WebSocket):
        """Register a WebSocket connection for a job."""
        self._connections[job_id].append(ws)
        logger.debug("WS connect job=%d (total=%d)", job_id, len(self._connections[job_id]))

    def disconnect(self, job_id: int, ws: WebSocket):
        """Remove a WebSocket connection."""
        conns = self._connections.get(job_id, [])
        if ws in conns:
            conns.remove(ws)
        if not conns:
            self._connections.pop(job_id, None)
        logger.debug("WS disconnect job=%d", job_id)

    async def _send(self, job_id: int, payload: dict[str, Any]):
        """Send JSON payload to all connections for job_id. Silently drops disconnected ones."""
        conns = list(self._connections.get(job_id, []))
        dead = []
        for ws in conns:
            try:
                if ws.client_state == WebSocketState.CONNECTED:
                    await ws.send_text(json.dumps(payload))
                else:
                    dead.append(ws)
            except Exception:
                dead.append(ws)
        for ws in dead:
            self.disconnect(job_id, ws)

    async def send_progress(self, job_id: int, percent: int, segment: str = ""):
        await self._send(job_id, {
            "type": "progress",
            "percent": percent,
            "segment": segment,
        })

    async def send_log(self, job_id: int, message: str):
        await self._send(job_id, {
            "type": "log",
            "message": message,
        })

    async def send_done(self, job_id: int, status: str, output_path: str | None):
        await self._send(job_id, {
            "type": "done",
            "status": status,
            "output_path": output_path,
        })

    async def send_error(self, job_id: int, message: str):
        await self._send(job_id, {
            "type": "error",
            "message": message,
        })

    def has_connections(self, job_id: int) -> bool:
        return bool(self._connections.get(job_id))


# Singleton instance used throughout the application
manager = ConnectionManager()
