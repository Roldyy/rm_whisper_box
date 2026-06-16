"""
whisper_runner.py — transcription service (faster-whisper backend).

Avantages de faster-whisper vs openai-whisper :
- Installe sans problème sur macOS (pas de dépendance à pkg_resources)
- 4× plus rapide, moins de VRAM (CTranslate2, pas PyTorch)
- Génère les segments un à un → progression native, pas de monkey-patch tqdm
- Supporte les mêmes modèles (tiny, base, small, medium, large-v2, large-v3, large-v3-turbo)
"""

import asyncio
import io
import json
import logging
import subprocess
import threading
import time
from datetime import datetime
from pathlib import Path
from typing import Callable

from config import TRANSCRIPTS_DIR
from services import status_bridge

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Model cache (module-level — survives between jobs)
# ---------------------------------------------------------------------------
_model_cache: dict = {}


# ---------------------------------------------------------------------------
# Model loading
# ---------------------------------------------------------------------------

def load_model(name: str):
    """
    Load faster-whisper model with optimal compute type.
    Returns (model, device_used).
    Caches in memory between jobs.

    faster-whisper uses CTranslate2 — MPS non supporté, int8 CPU est optimal
    sur Apple Silicon (performance correcte, faible consommation mémoire).
    """
    from faster_whisper import WhisperModel

    if name in _model_cache:
        return _model_cache[name], "cpu"

    # int8 = meilleur compromis vitesse/qualité sur CPU Apple Silicon
    model = WhisperModel(name, device="cpu", compute_type="int8")
    _model_cache[name] = model
    logger.info("Modèle %s chargé (cpu/int8)", name)
    return model, "cpu"


# ---------------------------------------------------------------------------
# Audio duration via ffprobe
# ---------------------------------------------------------------------------

def get_audio_duration(path: str) -> float | None:
    """Return audio duration in seconds using ffprobe. Returns None on failure."""
    try:
        r = subprocess.run(
            ["ffprobe", "-v", "quiet", "-print_format", "json", "-show_format", path],
            capture_output=True, text=True, timeout=10,
        )
        return float(json.loads(r.stdout)["format"]["duration"])
    except Exception:
        return None


# ---------------------------------------------------------------------------
# ffmpeg / ffprobe availability check
# ---------------------------------------------------------------------------

def check_ffmpeg() -> tuple[bool, str]:
    """Return (available: bool, version: str)."""
    try:
        r = subprocess.run(
            ["ffprobe", "-version"],
            capture_output=True, text=True, timeout=10,
        )
        if r.returncode == 0:
            first_line = r.stdout.splitlines()[0] if r.stdout else ""
            version = first_line.replace("ffprobe version ", "").split(" ")[0]
            return True, version
        return False, ""
    except Exception as e:
        return False, str(e)


# ---------------------------------------------------------------------------
# CancellationToken
# ---------------------------------------------------------------------------

class CancellationToken:
    def __init__(self):
        self._event = threading.Event()

    def cancel(self):
        self._event.set()

    @property
    def is_cancelled(self) -> bool:
        return self._event.is_set()


_active_tokens: dict[int, CancellationToken] = {}


def cancel_job(job_id: int):
    token = _active_tokens.get(job_id)
    if token:
        token.cancel()
        logger.info("Annulation demandée pour job %d", job_id)


# ---------------------------------------------------------------------------
# _write_output — write transcription result to file
# ---------------------------------------------------------------------------

def _write_output(
    segments: list,
    full_text: str,
    detected_language: str,
    stem: str,
    output_format: str,
    output_dir: Path,
    meta: dict,
) -> Path:
    """Write faster-whisper result to the appropriate file format."""
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filename = f"{stem}_{timestamp}.{output_format}"
    output_path = output_dir / filename

    if output_format == "txt":
        output_path.write_text(full_text, encoding="utf-8")

    elif output_format == "json":
        data = {
            "text": full_text,
            "language": detected_language,
            "segments": [
                {
                    "start": seg.start,
                    "end": seg.end,
                    "text": seg.text.strip(),
                    "words": [
                        {"word": w.word, "start": w.start, "end": w.end, "probability": w.probability}
                        for w in (seg.words or [])
                    ] if seg.words else [],
                }
                for seg in segments
            ],
        }
        output_path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")

    elif output_format == "srt":
        lines = []
        for i, seg in enumerate(segments, start=1):
            start = _format_srt_time(seg.start)
            end = _format_srt_time(seg.end)
            lines.append(f"{i}\n{start} --> {end}\n{seg.text.strip()}\n")
        output_path.write_text("\n".join(lines), encoding="utf-8")

    elif output_format == "vtt":
        lines = ["WEBVTT\n"]
        for seg in segments:
            start = _format_vtt_time(seg.start)
            end = _format_vtt_time(seg.end)
            lines.append(f"{start} --> {end}\n{seg.text.strip()}\n")
        output_path.write_text("\n".join(lines), encoding="utf-8")

    elif output_format == "tsv":
        lines = ["start\tend\ttext"]
        for seg in segments:
            lines.append(f"{seg.start:.3f}\t{seg.end:.3f}\t{seg.text.strip()}")
        output_path.write_text("\n".join(lines), encoding="utf-8")

    elif output_format == "md":
        word_ts = meta.get("word_timestamps", False)
        lines = [
            f"# Transcription : {stem}",
            "",
            f"**Date** : {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
            f"**Modèle** : {meta.get('model', '—')}",
            f"**Langue détectée** : {detected_language or '—'}",
            f"**Durée** : {meta.get('duration', '—')}",
            "",
            "---",
            "",
        ]
        if word_ts:
            for seg in segments:
                ts = _format_md_timestamp(seg.start)
                lines.append(f"[{ts}] {seg.text.strip()}")
                lines.append("")
        else:
            lines.append(full_text.strip())
        output_path.write_text("\n".join(lines), encoding="utf-8")

    else:
        output_path.write_text(full_text, encoding="utf-8")

    return output_path


def _format_srt_time(s: float) -> str:
    h, s = divmod(s, 3600); m, s = divmod(s, 60)
    return f"{int(h):02d}:{int(m):02d}:{int(s):02d},{int((s % 1) * 1000):03d}"

def _format_vtt_time(s: float) -> str:
    h, s = divmod(s, 3600); m, s = divmod(s, 60)
    return f"{int(h):02d}:{int(m):02d}:{int(s):02d}.{int((s % 1) * 1000):03d}"

def _format_md_timestamp(s: float) -> str:
    h, s = divmod(s, 3600); m, s = divmod(s, 60)
    return f"{int(h):02d}:{int(m):02d}:{int(s):02d}"


# ---------------------------------------------------------------------------
# _transcribe_in_thread — runs in asyncio.to_thread
# ---------------------------------------------------------------------------

def _transcribe_in_thread(
    model,
    audio_path: str,
    cancel_token: CancellationToken,
    progress_cb: Callable[[int, str], None],
    audio_duration: float | None,
    **kwargs,
) -> tuple[list, str]:
    """
    Run faster-whisper transcription synchronously (called via asyncio.to_thread).
    Returns (segments_list, full_text).

    Progress is natural: faster-whisper yields one segment at a time.
    No tqdm monkey-patch needed.
    """
    segments_iter, info = model.transcribe(audio_path, **kwargs)

    total_duration = audio_duration or getattr(info, "duration", None) or 0
    collected_segments = []
    text_parts = []

    for segment in segments_iter:
        if cancel_token.is_cancelled:
            raise InterruptedError("Annulé par l'utilisateur")

        collected_segments.append(segment)
        text_parts.append(segment.text)

        # Natural progress from segment timestamps
        if total_duration > 0:
            pct = min(int((segment.end / total_duration) * 100), 99)
        else:
            pct = 0

        progress_cb(pct, f"[{_format_md_timestamp(segment.start)}] {segment.text.strip()[:60]}")

    return collected_segments, "".join(text_parts)


# ---------------------------------------------------------------------------
# run_job — main orchestrator
# ---------------------------------------------------------------------------

async def run_job(job_id: int, db_session, ws_manager):
    from sqlalchemy import select
    from models.job import TranscriptionJob
    from models.log import ExecutionLog

    t_start = time.time()
    log_buffer = io.StringIO()
    token = CancellationToken()
    _active_tokens[job_id] = token

    def log(msg: str):
        log_buffer.write(msg + "\n")
        logger.info("[job %d] %s", job_id, msg)

    try:
        # 1. Fetch job
        result = await db_session.execute(
            select(TranscriptionJob).where(TranscriptionJob.id == job_id)
        )
        job = result.scalar_one_or_none()
        if job is None:
            logger.error("Job %d introuvable", job_id)
            return

        # 2. Status → running
        job.status = "running"
        job.progress = 0
        await db_session.commit()
        status_bridge.push(True, 0)

        log(f"Démarrage — {job.source_filename}")
        log(f"Modèle : {job.model} | Langue : {job.language or 'auto'} | Format : {job.output_format}")
        await ws_manager.send_log(job_id, f"Démarrage : {job.source_filename}")

        # 3. Audio duration
        duration_audio = get_audio_duration(job.source_path)
        if duration_audio:
            job.duration_audio = duration_audio
            await db_session.commit()
            log(f"Durée audio : {duration_audio:.1f}s")

        # 4. Load model
        log(f"Chargement du modèle '{job.model}'...")
        model, device_used = load_model(job.model)
        job.device_used = device_used
        await db_session.commit()
        log(f"Modèle '{job.model}' chargé sur {device_used}/int8")
        await ws_manager.send_log(job_id, f"Modèle '{job.model}' prêt ({device_used})")

        # 5. Build faster-whisper kwargs
        fw_kwargs: dict = {
            "task": job.task or "transcribe",
            "word_timestamps": bool(job.word_timestamps),
            "condition_on_previous_text": bool(job.condition_on_previous_text),
            "temperature": job.temperature if job.temperature else 0.0,
            "beam_size": job.beam_size or 5,
            "best_of": job.best_of or 5,
            "compression_ratio_threshold": job.compression_ratio_threshold or 2.4,
            "no_speech_threshold": job.no_speech_threshold or 0.6,
            "vad_filter": True,  # Voice Activity Detection — réduit les hallucinations
        }
        if job.language:
            fw_kwargs["language"] = job.language
        if job.initial_prompt:
            fw_kwargs["initial_prompt"] = job.initial_prompt

        # fp16 → faster-whisper ne l'expose pas directement (géré par compute_type int8)

        # Progress callback — thread-safe via run_coroutine_threadsafe
        loop = asyncio.get_event_loop()

        def progress_cb(percent: int, message: str):
            asyncio.run_coroutine_threadsafe(
                _update_progress(db_session, ws_manager, job_id, percent, message),
                loop,
            )
            status_bridge.push(True, percent)

        log("Transcription en cours...")

        # 6. Run in thread
        try:
            segments, full_text = await asyncio.to_thread(
                _transcribe_in_thread,
                model,
                job.source_path,
                token,
                progress_cb,
                duration_audio,
                **fw_kwargs,
            )
        except InterruptedError:
            job.status = "cancelled"
            await db_session.commit()
            status_bridge.push(False)
            await ws_manager.send_done(job_id, "cancelled", None)
            log("Annulé par l'utilisateur")
            return

        # Langue détectée (non disponible directement depuis segments — on la déduit)
        detected_lang = job.language or "auto"
        job.detected_language = detected_lang
        await db_session.commit()

        # 7. Write output
        from security import validate_output_dir
        output_dir = validate_output_dir(job.output_dir if job.output_dir else None)
        stem = Path(job.source_filename).stem

        meta = {
            "model": job.model,
            "duration": f"{duration_audio:.1f}s" if duration_audio else "—",
            "word_timestamps": bool(job.word_timestamps),
        }
        output_path = _write_output(
            segments, full_text, detected_lang, stem,
            job.output_format, output_dir, meta,
        )
        log(f"Fichier écrit : {output_path}")

        # 8. Status → success
        duration_run = time.time() - t_start
        job.status = "success"
        job.progress = 100
        job.output_path = str(output_path)
        job.duration_run = duration_run
        job.updated_at = datetime.utcnow()
        await db_session.commit()

        status_bridge.push(False)
        await ws_manager.send_progress(job_id, 100, "Terminé")
        await ws_manager.send_done(job_id, "success", str(output_path))
        log(f"Terminé en {duration_run:.1f}s")

    except Exception as e:
        logger.exception("Erreur run_job %d", job_id)
        log(f"ERREUR : {e}")
        try:
            r2 = await db_session.execute(
                select(TranscriptionJob).where(TranscriptionJob.id == job_id)
            )
            j2 = r2.scalar_one_or_none()
            if j2:
                j2.status = "error"
                j2.error_message = str(e)
                j2.updated_at = datetime.utcnow()
                await db_session.commit()
        except Exception:
            pass
        status_bridge.push(False)
        await ws_manager.send_error(job_id, str(e))

    finally:
        _active_tokens.pop(job_id, None)
        log_text = log_buffer.getvalue()
        try:
            r3 = await db_session.execute(
                select(TranscriptionJob).where(TranscriptionJob.id == job_id)
            )
            j3 = r3.scalar_one_or_none()
            status_val = j3.status if j3 else "error"
            db_session.add(ExecutionLog(
                job_id=job_id,
                operation_type="transcription",
                status=status_val,
                log_content=log_text,
            ))
            await db_session.commit()
        except Exception as le:
            logger.warning("ExecutionLog non créé pour job %d: %s", job_id, le)


async def _update_progress(db_session, ws_manager, job_id: int, percent: int, message: str):
    try:
        from sqlalchemy import select
        from models.job import TranscriptionJob
        r = await db_session.execute(
            select(TranscriptionJob).where(TranscriptionJob.id == job_id)
        )
        job = r.scalar_one_or_none()
        if job and job.status == "running":
            job.progress = percent
            await db_session.commit()
        await ws_manager.send_progress(job_id, percent, message)
    except Exception as e:
        logger.debug("_update_progress error: %s", e)
