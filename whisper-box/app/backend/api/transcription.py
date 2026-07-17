"""
api/transcription.py — POST /api/transcribe, cancel, rerun endpoints.
"""

from datetime import datetime
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from config import SUPPORTED_MODELS, SUPPORTED_LANGUAGES, SUPPORTED_OUTPUT_FORMATS
from database import get_db
from models.job import TranscriptionJob
from security import validate_source_path, validate_output_dir
from services.job_queue import job_queue
from services import whisper_runner

router = APIRouter(prefix="/api", tags=["transcription"])


class TranscribeRequest(BaseModel):
    source_path: str
    model: str = "large-v3-turbo"
    language: str = ""
    output_format: str = "txt"
    output_dir: str = ""
    # Advanced Whisper options
    task: str = "transcribe"
    temperature: float = 0.0
    word_timestamps: bool = False
    initial_prompt: str | None = None
    condition_on_previous_text: bool = True
    compression_ratio_threshold: float = 2.4
    no_speech_threshold: float = 0.6


@router.post("/transcribe")
async def transcribe(
    req: TranscribeRequest,
    db: AsyncSession = Depends(get_db),
):
    """Create a transcription job and enqueue it."""
    # Validate source path
    try:
        resolved_source = validate_source_path(req.source_path)
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))

    # Validate model
    if req.model not in SUPPORTED_MODELS:
        raise HTTPException(
            status_code=422,
            detail=f"Modèle non supporté : '{req.model}'. Valeurs acceptées : {SUPPORTED_MODELS}",
        )

    # Validate language
    if req.language not in SUPPORTED_LANGUAGES:
        raise HTTPException(
            status_code=422,
            detail=f"Langue non supportée : '{req.language}'.",
        )

    # Validate output format
    if req.output_format not in SUPPORTED_OUTPUT_FORMATS:
        raise HTTPException(
            status_code=422,
            detail=f"Format non supporté : '{req.output_format}'. Valeurs acceptées : {SUPPORTED_OUTPUT_FORMATS}",
        )

    # Validate output dir
    try:
        validate_output_dir(req.output_dir or None)
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))

    # Create job
    job = TranscriptionJob(
        source_path=str(resolved_source),
        source_filename=resolved_source.name,
        model=req.model,
        language=req.language or None,
        output_format=req.output_format,
        output_dir=req.output_dir or None,
        status="pending",
        progress=0,
        task=req.task,
        temperature=req.temperature,
        word_timestamps=1 if req.word_timestamps else 0,
        initial_prompt=req.initial_prompt,
        condition_on_previous_text=1 if req.condition_on_previous_text else 0,
        compression_ratio_threshold=req.compression_ratio_threshold,
        no_speech_threshold=req.no_speech_threshold,
    )
    db.add(job)
    await db.commit()
    await db.refresh(job)

    # Enqueue
    await job_queue.add_job(job.id)

    return {"job_id": job.id, "status": "pending"}


@router.post("/jobs/{job_id}/cancel")
async def cancel_job(job_id: int, db: AsyncSession = Depends(get_db)):
    """Soft-cancel a running job."""
    result = await db.execute(
        select(TranscriptionJob).where(TranscriptionJob.id == job_id)
    )
    job = result.scalar_one_or_none()
    if not job:
        raise HTTPException(status_code=404, detail=f"Job {job_id} introuvable")

    if job.status not in ("pending", "running"):
        raise HTTPException(
            status_code=400,
            detail=f"Job {job_id} ne peut pas être annulé (statut: {job.status})",
        )

    # Signal cancellation token
    whisper_runner.cancel_job(job_id)

    # Mark as cancelled (the worker will also set it when it catches InterruptedError)
    job.status = "cancelled"
    job.updated_at = datetime.utcnow()
    await db.commit()

    return {"job_id": job_id, "status": "cancelled"}


@router.post("/jobs/{job_id}/rerun")
async def rerun_job(job_id: int, db: AsyncSession = Depends(get_db)):
    """Clone an existing job and enqueue the clone."""
    result = await db.execute(
        select(TranscriptionJob).where(TranscriptionJob.id == job_id)
    )
    original = result.scalar_one_or_none()
    if not original:
        raise HTTPException(status_code=404, detail=f"Job {job_id} introuvable")

    # Clone the job
    new_job = TranscriptionJob(
        source_path=original.source_path,
        source_filename=original.source_filename,
        model=original.model,
        language=original.language,
        output_format=original.output_format,
        output_dir=original.output_dir,
        status="pending",
        progress=0,
        task=original.task,
        temperature=original.temperature,
        word_timestamps=original.word_timestamps,
        initial_prompt=original.initial_prompt,
        condition_on_previous_text=original.condition_on_previous_text,
        compression_ratio_threshold=original.compression_ratio_threshold,
        no_speech_threshold=original.no_speech_threshold,
    )
    db.add(new_job)
    await db.commit()
    await db.refresh(new_job)

    # Enqueue
    await job_queue.add_job(new_job.id)

    return {"job_id": new_job.id, "status": "pending"}
