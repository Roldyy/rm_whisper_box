"""
api/recording.py — POST /api/recording/start, /stop, GET /status
"""

from datetime import datetime
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from config import DATA_DIR
from database import get_db
from models.job import TranscriptionJob
from services.job_queue import job_queue
from services.recording_service import recording_service

router = APIRouter(prefix="/api/recording", tags=["recording"])

RECORDINGS_DIR = DATA_DIR / "recordings"

# Transcription settings stored at start, consumed at stop
_pending: dict = {}


class StartRecordingRequest(BaseModel):
    capture_mic: bool = False
    model: str = "large-v3-turbo"
    language: str = ""
    output_format: str = "txt"
    output_dir: str = ""
    task: str = "transcribe"
    word_timestamps: bool = False
    initial_prompt: str | None = None
    temperature: float = 0.0
    condition_on_previous_text: bool = True
    compression_ratio_threshold: float = 2.4
    no_speech_threshold: float = 0.6


@router.post("/start")
async def start_recording(req: StartRecordingRequest):
    global _pending

    if recording_service.is_recording:
        raise HTTPException(status_code=409, detail="Enregistrement déjà en cours")

    RECORDINGS_DIR.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_path = RECORDINGS_DIR / f"recording_{timestamp}.wav"

    try:
        await recording_service.start(output_path, req.capture_mic)
    except FileNotFoundError as e:
        raise HTTPException(status_code=500, detail=str(e))
    except RuntimeError as e:
        raise HTTPException(status_code=409, detail=str(e))

    _pending = req.model_dump()

    return {"status": "recording", "output_path": str(output_path)}


@router.post("/stop")
async def stop_recording(db: AsyncSession = Depends(get_db)):
    global _pending

    if not recording_service.is_recording:
        raise HTTPException(status_code=409, detail="Aucun enregistrement en cours")

    wav_path = await recording_service.stop()

    if wav_path is None or not wav_path.exists():
        raise HTTPException(status_code=500, detail="Fichier audio introuvable après arrêt")

    settings = _pending
    _pending = {}

    job = TranscriptionJob(
        source_path=str(wav_path),
        source_filename=wav_path.name,
        model=settings.get("model", "large-v3-turbo"),
        language=settings.get("language") or None,
        output_format=settings.get("output_format", "txt"),
        output_dir=settings.get("output_dir") or None,
        status="pending",
        progress=0,
        task=settings.get("task", "transcribe"),
        temperature=settings.get("temperature", 0.0),
        word_timestamps=1 if settings.get("word_timestamps") else 0,
        initial_prompt=settings.get("initial_prompt"),
        condition_on_previous_text=1 if settings.get("condition_on_previous_text", True) else 0,
        compression_ratio_threshold=settings.get("compression_ratio_threshold", 2.4),
        no_speech_threshold=settings.get("no_speech_threshold", 0.6),
    )
    db.add(job)
    await db.commit()
    await db.refresh(job)
    await job_queue.add_job(job.id)

    return {"job_id": job.id, "status": "pending"}


@router.get("/status")
async def get_status():
    return {
        "is_recording": recording_service.is_recording,
        "elapsed_seconds": recording_service.elapsed_seconds,
    }
