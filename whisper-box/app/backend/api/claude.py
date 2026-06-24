"""api/claude.py — Claude enhancement endpoints.

Routes:
  GET    /api/claude/status                      → CLI + auth state
  POST   /api/claude/token                       → save OAuth token to Keychain
  DELETE /api/claude/token                       → remove OAuth token
  POST   /api/claude/verify                      → test prompt to confirm token works
  POST   /api/claude/transcripts/{job_id}/enhance → run Claude on a completed transcript
"""

from datetime import datetime
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from models.setting import Setting
from services.keychain import delete_token, set_token
from services.claude_runner import check_claude, enhance_text

router = APIRouter(prefix="/api/claude", tags=["claude"])


# ── Status ─────────────────────────────────────────────────────────────────


@router.get("/status")
async def claude_status():
    """Return Claude CLI availability and auth state."""
    return check_claude()


# ── Token management ───────────────────────────────────────────────────────


class TokenBody(BaseModel):
    token: str


@router.post("/token")
async def save_token(body: TokenBody, db: AsyncSession = Depends(get_db)):
    """Store OAuth token in macOS Keychain and set claude_token_present flag in DB."""
    if not body.token.strip():
        raise HTTPException(status_code=400, detail="Token vide.")
    try:
        set_token(body.token.strip())
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Erreur Keychain : {e}")

    await _upsert_setting(db, "claude_token_present", "true")
    await db.commit()
    return {"saved": True}


@router.delete("/token")
async def remove_token(db: AsyncSession = Depends(get_db)):
    """Remove OAuth token from macOS Keychain."""
    delete_token()
    await _upsert_setting(db, "claude_token_present", "false")
    await db.commit()
    return {"deleted": True}


# ── Verify ─────────────────────────────────────────────────────────────────


@router.post("/verify")
async def verify_token():
    """Run a tiny test prompt to confirm the token actually works."""
    status = check_claude()
    if not status["available"]:
        raise HTTPException(
            status_code=424,
            detail=status.get("error") or "Claude CLI non disponible.",
        )
    if not status["token_present"]:
        raise HTTPException(status_code=401, detail="Aucun token Claude configuré.")
    try:
        response = await enhance_text(
            "Réponds juste: OK",
            mode="summary",
            model="claude-haiku-4-5-20251001",
        )
        return {"ok": True, "response": response[:200]}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ── Manual enhance ─────────────────────────────────────────────────────────


class EnhanceBody(BaseModel):
    mode: str = "summary"
    model: str = "claude-opus-4-8"


@router.post("/transcripts/{job_id}/enhance")
async def enhance_transcript(
    job_id: int,
    body: EnhanceBody,
    db: AsyncSession = Depends(get_db),
):
    """Run Claude enhancement on an already-completed transcript."""
    from models.job import TranscriptionJob

    result = await db.execute(
        select(TranscriptionJob).where(TranscriptionJob.id == job_id)
    )
    job = result.scalar_one_or_none()
    if job is None:
        raise HTTPException(status_code=404, detail="Job introuvable.")
    if job.status != "success":
        raise HTTPException(status_code=400, detail="Le job n'est pas terminé avec succès.")
    if not job.output_path:
        raise HTTPException(status_code=400, detail="Pas de fichier de sortie associé.")

    output = Path(job.output_path)
    if not output.exists():
        raise HTTPException(status_code=404, detail="Fichier de sortie introuvable sur le disque.")

    text = output.read_text(encoding="utf-8")
    if not text.strip():
        raise HTTPException(status_code=400, detail="Transcription vide.")

    status = check_claude()
    if not status["available"]:
        raise HTTPException(
            status_code=424,
            detail=status.get("error") or "Claude CLI non disponible.",
        )
    if not status["token_present"]:
        raise HTTPException(status_code=401, detail="Aucun token Claude configuré.")

    try:
        enhanced = await enhance_text(text, mode=body.mode, model=body.model)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    # Use the base stem without any prior .summary/.cleanup suffixes
    base_stem = output.stem.split(".")[0]
    summary_path = output.parent / f"{base_stem}_{timestamp}.{body.mode}.md"
    summary_path.write_text(enhanced, encoding="utf-8")

    return {
        "job_id": job_id,
        "mode": body.mode,
        "model": body.model,
        "summary_path": str(summary_path),
        "content": enhanced,
    }


# ── Helpers ────────────────────────────────────────────────────────────────


async def _upsert_setting(db: AsyncSession, key: str, value: str) -> None:
    result = await db.execute(select(Setting).where(Setting.key == key))
    existing = result.scalar_one_or_none()
    if existing:
        existing.value = value
    else:
        db.add(Setting(key=key, value=value))
