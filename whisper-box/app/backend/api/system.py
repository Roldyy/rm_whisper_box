"""
api/system.py — file upload endpoint.

Replaces the old native `osascript` file picker. A panel presented by the
background/accessory menu-bar process was slow to appear; instead the browser
shows its own instant file dialog and uploads the chosen file here. We stream it
to the uploads directory and return its absolute path for the normal
transcription flow.
"""

import asyncio
import logging
import time
from datetime import datetime
from pathlib import Path

import aiofiles
from fastapi import APIRouter, File, HTTPException, UploadFile

from config import DATA_DIR, SUPPORTED_EXTENSIONS

router = APIRouter(prefix="/api", tags=["system"])
logger = logging.getLogger(__name__)

UPLOADS_DIR = DATA_DIR / "uploads"
_CHUNK = 1024 * 1024  # 1 MiB — stream to disk so large media never loads fully in RAM
UPLOAD_RETENTION_DAYS = 7  # uploads older than this are pruned on startup


def prune_uploads(max_age_days: int = UPLOAD_RETENTION_DAYS) -> int:
    """Delete upload files older than max_age_days. Returns the number removed.

    Uploads are throwaway intermediates — the transcription output is written
    elsewhere — so this just reclaims disk space. Recent uploads are kept so a
    user can re-transcribe without re-uploading.
    """
    if not UPLOADS_DIR.exists():
        return 0
    cutoff = time.time() - max_age_days * 86400
    removed = 0
    for p in UPLOADS_DIR.iterdir():
        try:
            if p.is_file() and p.stat().st_mtime < cutoff:
                p.unlink()
                removed += 1
        except Exception:
            logger.warning("Impossible de supprimer l'upload %s", p, exc_info=True)
    if removed:
        logger.info("Prune : %d ancien(s) fichier(s) d'upload supprimé(s)", removed)
    return removed


@router.post("/upload")
async def upload_file(file: UploadFile = File(...)):
    """Save an uploaded media file to disk and return its absolute path."""
    original = Path(file.filename or "").name
    if not original:
        raise HTTPException(status_code=422, detail="Nom de fichier manquant.")

    ext = Path(original).suffix.lower()
    if ext not in SUPPORTED_EXTENSIONS:
        supported = ", ".join(sorted(SUPPORTED_EXTENSIONS))
        raise HTTPException(
            status_code=422,
            detail=f"Extension non supportée : '{ext}'. Extensions acceptées : {supported}",
        )

    UPLOADS_DIR.mkdir(parents=True, exist_ok=True)

    # Timestamp-prefix to avoid clobbering a previous upload of the same name.
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    dest = UPLOADS_DIR / f"{Path(original).stem}_{timestamp}{ext}"

    try:
        async with aiofiles.open(dest, "wb") as out:
            while chunk := await file.read(_CHUNK):
                await out.write(chunk)
    except Exception as e:
        logger.exception("Upload échoué")
        # Don't leave a half-written file behind.
        dest.unlink(missing_ok=True)
        raise HTTPException(status_code=500, detail=f"Échec de l'enregistrement : {e}")
    finally:
        await file.close()

    logger.info("Fichier téléversé : %s", dest)

    # Prune old uploads on each upload too, so the directory doesn't grow
    # between restarts. Off the event loop — it's filesystem I/O. The fresh
    # upload is well within the retention window, so it's never touched.
    await asyncio.to_thread(prune_uploads)

    return {"path": str(dest), "filename": original}
