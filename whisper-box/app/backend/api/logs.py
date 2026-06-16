"""
api/logs.py — GET/DELETE /api/logs
"""

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Response
from sqlalchemy import select, delete
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from models.log import ExecutionLog

router = APIRouter(prefix="/api", tags=["logs"])


@router.get("/logs")
async def list_logs(
    status: Optional[str] = None,
    limit: int = 50,
    offset: int = 0,
    db: AsyncSession = Depends(get_db),
):
    """List logs without log_content (summary only), DESC created_at."""
    stmt = select(ExecutionLog).order_by(ExecutionLog.created_at.desc())

    if status:
        stmt = stmt.where(ExecutionLog.status == status)

    stmt = stmt.limit(limit).offset(offset)
    result = await db.execute(stmt)
    logs = result.scalars().all()

    return [_log_to_dict(log, include_content=False) for log in logs]


@router.get("/logs/{log_id}")
async def get_log(log_id: int, db: AsyncSession = Depends(get_db)):
    """Get full log including log_content."""
    result = await db.execute(
        select(ExecutionLog).where(ExecutionLog.id == log_id)
    )
    log = result.scalar_one_or_none()
    if not log:
        raise HTTPException(status_code=404, detail=f"Log {log_id} introuvable")
    return _log_to_dict(log, include_content=True)


@router.delete("/logs/{log_id}", status_code=204)
async def delete_log(log_id: int, db: AsyncSession = Depends(get_db)):
    """Delete a log entry."""
    result = await db.execute(
        select(ExecutionLog).where(ExecutionLog.id == log_id)
    )
    log = result.scalar_one_or_none()
    if not log:
        raise HTTPException(status_code=404, detail=f"Log {log_id} introuvable")

    await db.execute(
        delete(ExecutionLog).where(ExecutionLog.id == log_id)
    )
    await db.commit()
    return Response(status_code=204)


def _log_to_dict(log: ExecutionLog, include_content: bool = False) -> dict:
    d = {
        "id": log.id,
        "job_id": log.job_id,
        "operation_type": log.operation_type,
        "status": log.status,
        "created_at": log.created_at.isoformat() if log.created_at else None,
    }
    if include_content:
        d["log_content"] = log.log_content
    return d
