"""claude_runner.py — Claude CLI subprocess wrapper for transcript enhancement.

Runs `claude -p --model <model>` as a subprocess, authenticated via
CLAUDE_CODE_OAUTH_TOKEN from Keychain. ANTHROPIC_API_KEY is explicitly stripped
from the subprocess env so it never bills per-token instead of using the subscription.
"""

import asyncio
import logging
import os
import shutil
import subprocess
from typing import Any, Callable

logger = logging.getLogger(__name__)

CLAUDE_MODELS = ["claude-opus-4-8", "claude-sonnet-4-6", "claude-haiku-4-5-20251001"]

# Common install locations for claude CLI (Homebrew, npm global, nvm, etc.)
_EXTRA_PATHS = [
    "/opt/homebrew/bin",
    "/usr/local/bin",
    os.path.expanduser("~/.npm-global/bin"),
    os.path.expanduser("~/.npm/bin"),
    os.path.expanduser("~/.nvm/versions/node/*/bin"),
]


def _find_claude() -> str:
    """Return the absolute path to the claude binary, or 'claude' as fallback."""
    extra = ":".join(_EXTRA_PATHS)
    search_path = extra + ":" + os.environ.get("PATH", "")
    found = shutil.which("claude", path=search_path)
    return found or "claude"


_CLAUDE_BIN = _find_claude()

_PROMPTS: dict[str, str] = {
    "summary": (
        "Tu es un assistant qui résume des transcriptions audio.\n"
        "Produis un résumé concis (5-10 points clés) de la transcription ci-dessous.\n"
        "Réponds dans la langue de la transcription.\n\n"
        "Transcription :\n"
    ),
    "cleanup": (
        "Tu es un assistant qui nettoie des transcriptions audio.\n"
        "Corrige la ponctuation, les fautes de frappe et la mise en forme.\n"
        "Ne change pas le sens ni le contenu. Conserve les pauses naturelles.\n\n"
        "Transcription :\n"
    ),
    "action-items": (
        "Tu es un assistant qui extrait les actions à réaliser depuis une transcription.\n"
        "Liste chaque action sous forme de bullet point avec un responsable si mentionné.\n"
        "Réponds dans la langue de la transcription.\n\n"
        "Transcription :\n"
    ),
}


def check_claude() -> dict:
    """Check Claude CLI availability and auth state.

    Mirrors the check_ffmpeg() pattern from whisper_runner.
    Returns: available, version, token_present, api_key_conflict, error.
    """
    from services.keychain import get_token

    result: dict = {
        "available": False,
        "version": "",
        "token_present": False,
        "api_key_conflict": False,
        "error": None,
    }
    try:
        r = subprocess.run(
            [_CLAUDE_BIN, "--version"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        if r.returncode == 0:
            result["available"] = True
            result["version"] = (r.stdout.strip().splitlines() or [""])[0]
        else:
            result["error"] = (
                f"Claude CLI introuvable ({_CLAUDE_BIN}). "
                "Installez @anthropic-ai/claude-code via npm/Node.js."
            )
            return result
    except FileNotFoundError:
        result["error"] = (
            f"Claude CLI introuvable ({_CLAUDE_BIN}). "
            "Installez @anthropic-ai/claude-code via npm/Node.js."
        )
        return result
    except Exception as e:
        result["error"] = str(e)
        return result

    result["token_present"] = get_token() is not None
    result["api_key_conflict"] = "ANTHROPIC_API_KEY" in os.environ
    return result


def _build_env() -> dict:
    """Return a clean subprocess env: inject OAuth token, strip ANTHROPIC_API_KEY."""
    from services.keychain import get_token

    env = os.environ.copy()
    # Critical: remove API key so subscription is used, not per-token billing
    env.pop("ANTHROPIC_API_KEY", None)
    token = get_token()
    if token:
        env["CLAUDE_CODE_OAUTH_TOKEN"] = token
    return env


def _enhance_in_thread(
    text: str,
    mode: str,
    model: str,
    cancel_token: Any,
    progress_cb: Callable[[int, str], None] | None,
) -> str:
    """Run `claude -p` synchronously. Called via asyncio.to_thread."""
    prompt_prefix = _PROMPTS.get(mode, _PROMPTS["summary"])
    full_prompt = prompt_prefix + text

    cmd = [_CLAUDE_BIN, "-p", "--model", model]
    env = _build_env()

    if progress_cb:
        progress_cb(10, "Envoi au modèle Claude…")

    logger.info("claude enhance | mode=%s model=%s prompt_len=%d", mode, model, len(full_prompt))

    proc = subprocess.Popen(
        cmd,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
    )

    logger.info("claude enhance | pid=%d sent to claude, waiting…", proc.pid)

    try:
        stdout, stderr = proc.communicate(input=full_prompt, timeout=300)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.communicate()
        raise TimeoutError("Claude CLI a dépassé le délai de 5 minutes.")

    if cancel_token and getattr(cancel_token, "is_cancelled", False):
        proc.kill()
        raise InterruptedError("Enhancement annulé par l'utilisateur.")

    if proc.returncode != 0:
        error_detail = stderr.strip()[:500] if stderr else "(aucun détail)"
        logger.error("claude enhance | failed code=%d %s", proc.returncode, error_detail)
        raise RuntimeError(
            f"Claude CLI a échoué (code {proc.returncode}) : {error_detail}"
        )

    logger.info("claude enhance | done output_len=%d", len(stdout))

    if progress_cb:
        progress_cb(90, "Réponse reçue…")

    return stdout.strip()


async def enhance_text(
    text: str,
    mode: str = "summary",
    model: str = "claude-opus-4-8",
    cancel_token: Any = None,
    progress_cb: Callable[[int, str], None] | None = None,
) -> str:
    """Run Claude enhancement asynchronously (asyncio.to_thread wrapper)."""
    return await asyncio.to_thread(
        _enhance_in_thread, text, mode, model, cancel_token, progress_cb,
    )
