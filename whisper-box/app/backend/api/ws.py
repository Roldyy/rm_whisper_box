"""
api/ws.py — WebSocket endpoint /api/ws/{job_id}

- If job is already success/error/cancelled: send done/error immediately and close
- Otherwise: register in ConnectionManager and stream until done/error/disconnect
"""

import json
import logging

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from database import AsyncSessionLocal
from models.job import TranscriptionJob
from services.ws_manager import manager

router = APIRouter(tags=["ws"])
logger = logging.getLogger(__name__)


@router.websocket("/api/ws/{job_id}")
async def websocket_endpoint(websocket: WebSocket, job_id: int):
    await websocket.accept()

    async with AsyncSessionLocal() as db:
        result = await db.execute(
            select(TranscriptionJob).where(TranscriptionJob.id == job_id)
        )
        job = result.scalar_one_or_none()

    if not job:
        await websocket.send_text(
            json.dumps({"type": "error", "message": f"Job {job_id} introuvable"})
        )
        await websocket.close()
        return

    # If job is already terminal — send final state immediately
    if job.status == "success":
        await websocket.send_text(json.dumps({
            "type": "done",
            "status": "success",
            "output_path": job.output_path,
        }))
        await websocket.close()
        return

    if job.status in ("error",):
        await websocket.send_text(json.dumps({
            "type": "error",
            "message": job.error_message or "Erreur inconnue",
        }))
        await websocket.close()
        return

    if job.status == "cancelled":
        await websocket.send_text(json.dumps({
            "type": "done",
            "status": "cancelled",
            "output_path": None,
        }))
        await websocket.close()
        return

    # Job is pending or running — register and keep connection open
    manager.connect(job_id, websocket)
    try:
        # Send current progress if running
        if job.status == "running" and job.progress:
            await websocket.send_text(json.dumps({
                "type": "progress",
                "percent": job.progress,
                "segment": "",
            }))

        # Keep connection open until client disconnects
        while True:
            try:
                data = await websocket.receive_text()
                # We don't expect messages from client, but handle gracefully
                if data == "ping":
                    await websocket.send_text(json.dumps({"type": "pong"}))
            except WebSocketDisconnect:
                break

    except Exception as e:
        logger.debug("WS exception job=%d: %s", job_id, e)
    finally:
        manager.disconnect(job_id, websocket)
