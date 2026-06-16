"""
api/jobs.py — GET/DELETE /api/jobs
"""

import subprocess
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select, delete
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from models.job import TranscriptionJob

router = APIRouter(prefix="/api", tags=["jobs"])


@router.get("/jobs")
async def list_jobs(
    status: Optional[str] = None,
    search: Optional[str] = None,
    limit: int = 50,
    offset: int = 0,
    db: AsyncSession = Depends(get_db),
):
    """List jobs with optional filtering by status and filename search."""
    stmt = select(TranscriptionJob).order_by(TranscriptionJob.created_at.desc())

    if status:
        stmt = stmt.where(TranscriptionJob.status == status)

    if search:
        stmt = stmt.where(
            TranscriptionJob.source_filename.ilike(f"%{search}%")
        )

    stmt = stmt.limit(limit).offset(offset)
    result = await db.execute(stmt)
    jobs = result.scalars().all()

    return [_job_to_dict(j) for j in jobs]


@router.get("/jobs/{job_id}")
async def get_job(job_id: int, db: AsyncSession = Depends(get_db)):
    """Get full details of a job."""
    result = await db.execute(
        select(TranscriptionJob).where(TranscriptionJob.id == job_id)
    )
    job = result.scalar_one_or_none()
    if not job:
        raise HTTPException(status_code=404, detail=f"Job {job_id} introuvable")
    return _job_to_dict(job)


@router.post("/jobs/{job_id}/cancel", status_code=200)
async def cancel_job_endpoint(job_id: int):
    """Cancel a running transcription job."""
    from services.whisper_runner import cancel_job
    cancel_job(job_id)
    return {"cancelled": job_id}


@router.delete("/jobs/{job_id}", status_code=204)
async def delete_job(job_id: int, db: AsyncSession = Depends(get_db)):
    """Delete a job (and its logs via cascade). Does NOT delete the output file."""
    result = await db.execute(
        select(TranscriptionJob).where(TranscriptionJob.id == job_id)
    )
    job = result.scalar_one_or_none()
    if not job:
        raise HTTPException(status_code=404, detail=f"Job {job_id} introuvable")

    await db.execute(
        delete(TranscriptionJob).where(TranscriptionJob.id == job_id)
    )
    await db.commit()
    return None


@router.get("/jobs/{job_id}/open")
async def open_job_output(job_id: int, db: AsyncSession = Depends(get_db)):
    """Open the output file in the OS default application (macOS: open command)."""
    result = await db.execute(
        select(TranscriptionJob).where(TranscriptionJob.id == job_id)
    )
    job = result.scalar_one_or_none()
    if not job:
        raise HTTPException(status_code=404, detail=f"Job {job_id} introuvable")
    if not job.output_path:
        raise HTTPException(status_code=404, detail="Aucun fichier de sortie pour ce job")

    try:
        subprocess.run(["open", job.output_path], check=True)
    except subprocess.CalledProcessError as e:
        raise HTTPException(status_code=500, detail=f"Impossible d'ouvrir le fichier : {e}")

    return {"opened": job.output_path}


def _job_to_dict(job: TranscriptionJob) -> dict:
    return {
        "id": job.id,
        "source_path": job.source_path,
        "source_filename": job.source_filename,
        "model": job.model,
        "language": job.language,
        "output_format": job.output_format,
        "output_path": job.output_path,
        "status": job.status,
        "progress": job.progress,
        "duration_audio": job.duration_audio,
        "duration_run": job.duration_run,
        "device_used": job.device_used,
        "error_message": job.error_message,
        "created_at": job.created_at.isoformat() if job.created_at else None,
        "updated_at": job.updated_at.isoformat() if job.updated_at else None,
    }
