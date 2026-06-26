"""
whisper_runner.py — transcription service (mlx-whisper backend).

mlx-whisper avantages vs faster-whisper :
- Utilise le Apple Neural Engine via MLX → 5-10× plus rapide sur Apple Silicon
- Même API Whisper (modèles identiques, mêmes formats de sortie)
- Pas de CTranslate2 / CUDA — natif Apple Silicon
- Supporte tiny, base, small, medium, large-v2, large-v3, large-v3-turbo
"""

import asyncio
import io
import json
import logging
import os
import subprocess
import threading
import time
from datetime import datetime
from pathlib import Path
from types import SimpleNamespace
from typing import Callable

from config import TRANSCRIPTS_DIR
from services import status_bridge

# ---------------------------------------------------------------------------
# Bundled ffmpeg helpers — imageio-ffmpeg ships a static arm64 binary whose
# filename is versioned (e.g. ffmpeg-macos-aarch64-v7.1), not 'ffmpeg', so
# PATH tricks don't work. We use the full binary path directly.
# ---------------------------------------------------------------------------
def _get_ffmpeg_exe() -> str:
    """Return the bundled imageio-ffmpeg binary path, or 'ffmpeg' as fallback."""
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:
        return "ffmpeg"

def _get_ffprobe_exe() -> str:
    """Return ffprobe alongside the imageio-ffmpeg binary, or 'ffprobe' as fallback."""
    try:
        import imageio_ffmpeg
        p = Path(imageio_ffmpeg.get_ffmpeg_exe()).parent / "ffprobe"
        if p.exists():
            return str(p)
    except Exception:
        pass
    return "ffprobe"

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Model name → HuggingFace repo mapping (mlx-community)
# ---------------------------------------------------------------------------

_MODEL_REPO: dict[str, str] = {
    "tiny":            "mlx-community/whisper-tiny-mlx",
    "tiny.en":         "mlx-community/whisper-tiny.en-mlx",
    "base":            "mlx-community/whisper-base-mlx",
    "base.en":         "mlx-community/whisper-base.en-mlx",
    "small":           "mlx-community/whisper-small-mlx",
    "small.en":        "mlx-community/whisper-small.en-mlx",
    "medium":          "mlx-community/whisper-medium-mlx",
    "medium.en":       "mlx-community/whisper-medium.en-mlx",
    "large-v2":        "mlx-community/whisper-large-v2-mlx",
    "large-v3":        "mlx-community/whisper-large-v3-mlx",
    "large-v3-turbo":  "mlx-community/whisper-large-v3-turbo",
    "turbo":           "mlx-community/whisper-large-v3-turbo",
}

# Tracks repos already downloaded (mlx-whisper caches models via HF hub)
_model_cache: set[str] = set()


def _model_repo(name: str) -> str:
    """Map a short model name to its mlx-community HF repo. Falls back to name as-is."""
    return _MODEL_REPO.get(name, name)


# ---------------------------------------------------------------------------
# Model loading
# ---------------------------------------------------------------------------

def load_model(name: str):
    """
    Resolve model name to HF repo and pre-warm the mlx-whisper model cache.
    mlx-whisper downloads once to ~/.cache/huggingface/hub, then loads from disk.
    Returns (repo_path, device_used).
    """
    import mlx_whisper

    repo = _model_repo(name)
    if repo not in _model_cache:
        # Preload: mlx_whisper.load_models caches the model weights in MLX
        mlx_whisper.load_models.load_model(repo)
        _model_cache.add(repo)
        logger.info("Modèle %s chargé (mlx / Apple Neural Engine)", repo)
    return repo, "mlx"


# ---------------------------------------------------------------------------
# Audio duration via ffprobe
# ---------------------------------------------------------------------------

def get_audio_duration(path: str) -> float | None:
    """Return audio duration in seconds using ffprobe. Returns None on failure."""
    try:
        r = subprocess.run(
            [_get_ffprobe_exe(), "-v", "quiet", "-print_format", "json", "-show_format", path],
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
            [_get_ffprobe_exe(), "-version"],
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
    """Write mlx-whisper result to the appropriate file format."""
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
# _load_audio — decode audio to 16kHz mono float32 numpy array.
# Replicates mlx-whisper's internal load_audio but uses the bundled ffmpeg
# binary via its full path instead of relying on PATH lookup.
# ---------------------------------------------------------------------------

def _load_audio(path: str, sample_rate: int = 16000) -> "np.ndarray":
    import numpy as np
    cmd = [
        _get_ffmpeg_exe(),
        "-nostdin", "-threads", "0",
        "-i", path,
        "-f", "s16le", "-ac", "1", "-acodec", "pcm_s16le",
        "-ar", str(sample_rate),
        "pipe:1",
    ]
    out = subprocess.run(cmd, capture_output=True, check=True)
    return np.frombuffer(out.stdout, np.int16).flatten().astype(np.float32) / 32768.0


# ---------------------------------------------------------------------------
# _wrap_segment — normalise mlx-whisper dict segments to attribute-style objects
# ---------------------------------------------------------------------------

def _wrap_segment(d: dict) -> SimpleNamespace:
    words = []
    for w in d.get("words") or []:
        words.append(SimpleNamespace(
            word=w.get("word", ""),
            start=w.get("start", 0.0),
            end=w.get("end", 0.0),
            probability=w.get("probability", 1.0),
        ))
    return SimpleNamespace(
        start=d.get("start", 0.0),
        end=d.get("end", 0.0),
        text=d.get("text", ""),
        words=words or None,
    )


# ---------------------------------------------------------------------------
# _transcribe_in_thread — runs in asyncio.to_thread
# ---------------------------------------------------------------------------

def _transcribe_in_thread(
    repo: str,
    audio_path: str,
    cancel_token: CancellationToken,
    progress_cb: Callable[[int, str], None],
    audio_duration: float | None,
    **kwargs,
) -> tuple[list, str, str]:
    """
    Run mlx-whisper transcription synchronously (called via asyncio.to_thread).
    Returns (segments_list, full_text, detected_language).

    mlx-whisper returns all segments at once (not streaming). We replay them
    through the progress callback so the UI still shows real segment content.
    """
    import mlx_whisper

    # Decode audio ourselves so we control the ffmpeg binary path.
    # mlx-whisper accepts a numpy float32 array (16kHz mono) directly.
    audio_array = _load_audio(audio_path)
    result = mlx_whisper.transcribe(audio_array, path_or_hf_repo=repo, verbose=False, **kwargs)

    if cancel_token.is_cancelled:
        raise InterruptedError("Annulé par l'utilisateur")

    raw_segments = result.get("segments") or []
    detected_language = result.get("language") or ""
    full_text = result.get("text") or ""

    total_duration = audio_duration or (raw_segments[-1]["end"] if raw_segments else 0)
    segments = []

    for raw in raw_segments:
        if cancel_token.is_cancelled:
            raise InterruptedError("Annulé par l'utilisateur")

        seg = _wrap_segment(raw)
        segments.append(seg)

        pct = min(int((seg.end / total_duration) * 100), 99) if total_duration > 0 else 0
        progress_cb(pct, f"[{_format_md_timestamp(seg.start)}] {seg.text.strip()[:60]}")

    return segments, full_text, detected_language


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

    # Per-step timings (seconds), logged as a breakdown at the end.
    timings: dict[str, float] = {}

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
        # ffprobe is a blocking subprocess — run it off the event loop so WS
        # progress, recording status and other requests aren't frozen.
        _t = time.time()
        duration_audio = await asyncio.to_thread(get_audio_duration, job.source_path)
        timings["analyse_audio"] = time.time() - _t
        if duration_audio:
            job.duration_audio = duration_audio
            await db_session.commit()
            log(f"Durée audio : {duration_audio:.1f}s")
        log(f"⏱ Analyse audio (ffprobe) : {timings['analyse_audio']:.1f}s")

        # 4. Load model
        # Model load/download is blocking and can take seconds-to-minutes on the
        # first run — must run in a thread or the whole backend hangs meanwhile.
        # Warm runs hit the in-process cache and return near-instantly.
        log(f"Chargement du modèle '{job.model}'...")
        _t = time.time()
        repo, device_used = await asyncio.to_thread(load_model, job.model)
        timings["chargement_modele"] = time.time() - _t
        job.device_used = device_used
        await db_session.commit()
        log(f"Modèle '{job.model}' prêt ({device_used} / Apple Neural Engine)")
        log(f"⏱ Chargement du modèle : {timings['chargement_modele']:.1f}s")
        await ws_manager.send_log(job_id, f"Modèle '{job.model}' prêt ({device_used})")

        # 5. Build mlx-whisper kwargs
        mlx_kwargs: dict = {
            "task": job.task or "transcribe",
            "word_timestamps": bool(job.word_timestamps),
            "condition_on_previous_text": bool(job.condition_on_previous_text),
            # Temperature fallback ("auto-adjust"): when the user leaves the default
            # (0.0), pass Whisper's standard fallback schedule so a segment that fails
            # the compression-ratio / logprob guards is retried at a higher temperature.
            # This is what lets the decoder escape repetition/hallucination loops — the
            # cause of the intermittent >realtime slowdown on long, noisy recordings.
            # A single scalar 0.0 (the old value) disabled fallback entirely.
            # If the user explicitly sets a non-zero temperature, honor it verbatim.
            "temperature": (0.0, 0.2, 0.4, 0.6, 0.8, 1.0) if not job.temperature else job.temperature,
            "compression_ratio_threshold": job.compression_ratio_threshold or 2.4,
            "no_speech_threshold": job.no_speech_threshold or 0.6,
        }
        if job.language:
            mlx_kwargs["language"] = job.language
        if job.initial_prompt:
            mlx_kwargs["initial_prompt"] = job.initial_prompt

        # Progress callback — thread-safe via run_coroutine_threadsafe
        loop = asyncio.get_event_loop()

        def progress_cb(percent: int, message: str):
            asyncio.run_coroutine_threadsafe(
                _update_progress(ws_manager, job_id, percent, message),
                loop,
            )
            status_bridge.push(True, percent)

        log("Transcription en cours...")

        # 6. Run in thread
        _t = time.time()
        try:
            segments, full_text, detected_lang = await asyncio.to_thread(
                _transcribe_in_thread,
                repo,
                job.source_path,
                token,
                progress_cb,
                duration_audio,
                **mlx_kwargs,
            )
        except InterruptedError:
            job.status = "cancelled"
            await db_session.commit()
            status_bridge.push(False)
            await ws_manager.send_done(job_id, "cancelled", None)
            log("Annulé par l'utilisateur")
            return

        # Cancellation can arrive after transcription returns but before we
        # commit success. Honor it here so a finishing job doesn't overwrite a
        # user-requested cancel.
        if token.is_cancelled:
            job.status = "cancelled"
            await db_session.commit()
            status_bridge.push(False)
            await ws_manager.send_done(job_id, "cancelled", None)
            log("Annulé par l'utilisateur")
            return

        timings["transcription"] = time.time() - _t
        rtf = (
            f" ({duration_audio / timings['transcription']:.1f}× temps réel)"
            if duration_audio and timings["transcription"] > 0 else ""
        )
        log(f"⏱ Transcription : {timings['transcription']:.1f}s{rtf}")

        job.detected_language = detected_lang or job.language or "auto"
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
        _t = time.time()
        output_path = _write_output(
            segments, full_text, job.detected_language, stem,
            job.output_format, output_dir, meta,
        )
        timings["ecriture"] = time.time() - _t
        log(f"Fichier écrit : {output_path}")
        log(f"⏱ Écriture du fichier : {timings['ecriture']:.1f}s")

        # 7b. Auto-enhance with Claude if configured (non-fatal)
        try:
            from sqlalchemy import select as _select
            from models.setting import Setting as _Setting

            async def _get_setting(key: str) -> str | None:
                r = await db_session.execute(
                    _select(_Setting).where(_Setting.key == key)
                )
                s = r.scalar_one_or_none()
                return s.value if s else None

            claude_enabled = await _get_setting("claude_enabled")
            claude_auto = await _get_setting("claude_auto_after_transcribe")
            if claude_enabled == "true" and claude_auto == "true":
                from services.claude_runner import check_claude, enhance_text as _enhance
                claude_status = check_claude()
                if claude_status["available"] and claude_status["token_present"]:
                    await ws_manager.send_log(job_id, "Enhancement Claude en cours…")
                    claude_model = await _get_setting("claude_model") or "claude-opus-4-8"
                    claude_mode = await _get_setting("claude_default_mode") or "summary"
                    _t = time.time()
                    enhanced = await _enhance(
                        full_text, mode=claude_mode, model=claude_model,
                        cancel_token=token,
                    )
                    timings["enhancement_claude"] = time.time() - _t
                    ts2 = datetime.now().strftime("%Y%m%d_%H%M%S")
                    summary_path = output_dir / f"{stem}_{ts2}.{claude_mode}.md"
                    summary_path.write_text(enhanced, encoding="utf-8")
                    log(f"Enhancement Claude écrit : {summary_path}")
                    log(f"⏱ Enhancement Claude : {timings['enhancement_claude']:.1f}s")
                    await ws_manager.send_log(
                        job_id, f"Enhancement Claude terminé : {summary_path.name}"
                    )
                else:
                    log("Enhancement Claude ignoré (CLI non disponible ou token absent)")
        except Exception as _ce:
            log(f"Enhancement Claude (non-fatal) : {_ce}")
            await ws_manager.send_log(job_id, "Enhancement Claude échoué (non-bloquant)")

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

        # Per-step breakdown (the sum may be slightly under the total — DB
        # commits and overhead aren't attributed to any single step).
        _labels = {
            "analyse_audio": "Analyse audio",
            "chargement_modele": "Chargement modèle",
            "transcription": "Transcription",
            "ecriture": "Écriture fichier",
            "enhancement_claude": "Enhancement Claude",
        }
        breakdown = " · ".join(
            f"{_labels[k]} {timings[k]:.1f}s" for k in _labels if k in timings
        )
        log(f"⏱ Détail : {breakdown}")
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


async def _update_progress(ws_manager, job_id: int, percent: int, message: str):
    # Uses its own session to avoid corrupting the caller's transaction when
    # multiple progress callbacks run concurrently during transcription.
    try:
        from database import AsyncSessionLocal
        from sqlalchemy import select
        from models.job import TranscriptionJob
        async with AsyncSessionLocal() as session:
            r = await session.execute(
                select(TranscriptionJob).where(TranscriptionJob.id == job_id)
            )
            job = r.scalar_one_or_none()
            if job and job.status == "running":
                job.progress = percent
                await session.commit()
        await ws_manager.send_progress(job_id, percent, message)
    except Exception as e:
        logger.debug("_update_progress error: %s", e)
