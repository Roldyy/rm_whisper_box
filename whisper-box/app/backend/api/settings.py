"""
api/settings.py — GET/POST /api/settings, GET /api/health, open-data-dir
"""

import subprocess

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from config import APP_VERSION, DATA_DIR, WHISPER_MODELS_INFO
from database import get_db
from models.setting import Setting
from services.whisper_runner import check_ffmpeg

router = APIRouter(prefix="/api", tags=["settings"])


@router.get("/settings")
async def get_settings(db: AsyncSession = Depends(get_db)):
    """Return all settings as a flat key→value dict."""
    result = await db.execute(select(Setting))
    settings = result.scalars().all()
    return {s.key: s.value for s in settings}


@router.post("/settings")
async def update_settings(
    body: dict,
    db: AsyncSession = Depends(get_db),
):
    """Upsert settings. Body is a dict of {key: value}. Returns updated settings."""
    for key, value in body.items():
        result = await db.execute(select(Setting).where(Setting.key == key))
        existing = result.scalar_one_or_none()
        if existing:
            existing.value = str(value)
        else:
            db.add(Setting(key=key, value=str(value)))

    await db.commit()

    # Return all settings
    result = await db.execute(select(Setting))
    settings = result.scalars().all()
    return {s.key: s.value for s in settings}


@router.get("/health")
async def health():
    """Return backend health status."""
    ffmpeg_available, ffmpeg_version = check_ffmpeg()
    return {
        "status": "ok",
        "version": APP_VERSION,
        "ffmpeg_available": ffmpeg_available,
        "ffmpeg_version": ffmpeg_version,
        "device": "cpu",  # faster-whisper / CTranslate2 — MPS non supporté, toujours CPU
    }


@router.get("/whisper/models")
async def get_whisper_models():
    """Return list of available Whisper models with params/vram/speed info."""
    return [
        {"name": name, **info}
        for name, info in WHISPER_MODELS_INFO.items()
    ]


@router.post("/update")
async def update_app():
    """Run git pull in repo root, then trigger rebuild."""
    import subprocess as sp
    from config import REPO_ROOT
    if not REPO_ROOT:
        return {"status": "error", "message": "Répertoire du projet non trouvé."}
    try:
        git = sp.run(
            ["git", "pull"],
            cwd=str(REPO_ROOT),
            capture_output=True, text=True, timeout=30,
        )
    except Exception as e:
        return {"status": "error", "message": str(e)}
    if git.returncode != 0:
        return {"status": "error", "message": git.stderr or git.stdout}
    if "Already up to date" in git.stdout:
        return {"status": "up_to_date", "message": "Déjà à jour — aucune mise à jour disponible."}
    sp.Popen(
        ["bash", str(REPO_ROOT / "app" / "dev" / "create-app.command")],
        cwd=str(REPO_ROOT),
    )
    return {"status": "updating", "message": "Mise à jour téléchargée. Rebuild en cours — relancez l'application dans ~30 secondes."}


@router.get("/settings/open-data-dir")
async def open_data_dir():
    """Open the data directory in Finder (macOS)."""
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    try:
        subprocess.run(["open", str(DATA_DIR)], check=True)
    except subprocess.CalledProcessError as e:
        return {"error": str(e)}
    return {"opened": str(DATA_DIR)}
