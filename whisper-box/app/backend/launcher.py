"""
launcher.py — Entry point for the macOS .app bundle.

Architecture (Solution R2, MASTER_SPEC):
- uvicorn runs in a daemon thread (NEVER in the main thread)
- rumps.App.run() runs in the main thread (NSRunLoop — mandatory)
- status_bridge is imported from services.status_bridge (avoids circular imports)
- @rumps.timer reads the thread-safe queue.Queue — never asyncio code here
"""

import sys
import os
import subprocess
import threading
import time

# Ensure the backend directory is on sys.path so imports work from the .app bundle
_BACKEND_DIR = os.path.dirname(os.path.abspath(__file__))
if _BACKEND_DIR not in sys.path:
    sys.path.insert(0, _BACKEND_DIR)

import requests  # noqa: E402
import uvicorn   # noqa: E402
import rumps     # noqa: E402
from services.status_bridge import poll as _poll_status  # noqa: E402

APP_URL = "http://127.0.0.1:7843"


def _start_uvicorn():
    """MUST run in a daemon thread — never in the main thread."""
    uvicorn.run(
        "main:app",
        host="127.0.0.1",
        port=7843,
        log_level="warning",
        loop="asyncio",
    )


def _wait_for_backend(timeout: int = 30) -> bool:
    """Poll /api/health until the backend is ready or timeout expires."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            if requests.get(f"{APP_URL}/api/health", timeout=1).status_code == 200:
                return True
        except Exception:
            pass
        time.sleep(0.3)
    return False


def _open_browser(url: str):
    """Use macOS 'open' command — always works from a .app bundle."""
    subprocess.run(["open", url], check=False)


def _notify(title: str, subtitle: str, message: str):
    """Best-effort macOS notification — silently ignored if unavailable."""
    try:
        rumps.notification(title, subtitle, message)
    except Exception:
        pass


def _fmt_elapsed(seconds: float) -> str:
    s = int(seconds)
    return f"{s // 60:02d}:{s % 60:02d}"


class WhisperBoxMenuBar(rumps.App):
    def __init__(self):
        # Icon: in the .app bundle, icon.png sits alongside launcher.py in Resources/
        _icon_path = os.path.join(_BACKEND_DIR, "icon.png")
        _icon = _icon_path if os.path.isfile(_icon_path) else None
        super().__init__(
            "WB",
            icon=_icon,
            quit_button=None,
        )
        self._is_recording = False
        self._rec_elapsed = 0.0
        self._txn_running = False
        self._txn_percent = 0

        self._record_item = rumps.MenuItem(
            "Démarrer l'enregistrement", callback=self._toggle_recording
        )
        self.menu = [
            self._record_item,
            None,
            rumps.MenuItem("Ouvrir Whisper Box", callback=self._open),
            None,
            rumps.MenuItem("Quitter", callback=lambda _: rumps.quit_application()),
        ]

    def _open(self, _):
        _open_browser(APP_URL)

    def _toggle_recording(self, _):
        if self._is_recording:
            self._stop_recording()
        else:
            self._start_recording()

    def _start_recording(self):
        payload = {"capture_mic": True}  # mic always included for taskbar recordings
        # Apply the user's saved defaults, mirroring the web Record page.
        try:
            settings = requests.get(f"{APP_URL}/api/settings", timeout=2).json()
            for src, dst in (
                ("default_model", "model"),
                ("default_language", "language"),
                ("default_output_format", "output_format"),
                ("default_output_dir", "output_dir"),
            ):
                if settings.get(src):
                    payload[dst] = settings[src]
        except Exception:
            pass  # fall back to server-side defaults

        try:
            r = requests.post(f"{APP_URL}/api/recording/start", json=payload, timeout=5)
        except Exception as e:
            _notify("Whisper Box", "Erreur", str(e))
            return
        if r.status_code >= 400:
            detail = r.json().get("detail", "Échec du démarrage") if r.content else "Échec du démarrage"
            _notify("Whisper Box", "Enregistrement", detail)
            return
        self._set_recording(True)
        _notify("Whisper Box", "Enregistrement démarré", "Cliquez à nouveau pour arrêter et transcrire.")

    def _stop_recording(self):
        try:
            r = requests.post(f"{APP_URL}/api/recording/stop", timeout=15)
        except Exception as e:
            _notify("Whisper Box", "Erreur", str(e))
            return
        if r.status_code >= 400:
            detail = r.json().get("detail", "Échec de l'arrêt") if r.content else "Échec de l'arrêt"
            _notify("Whisper Box", "Enregistrement", detail)
            return
        self._set_recording(False)
        _notify("Whisper Box", "Enregistrement arrêté", "Transcription ajoutée à la file d'attente.")

    def _set_recording(self, recording: bool):
        self._is_recording = recording
        self._record_item.title = (
            "Arrêter l'enregistrement" if recording else "Démarrer l'enregistrement"
        )

    @rumps.timer(2)
    def _poll_status(self, _):
        """
        Runs in the main thread — reads the status_bridge queue.Queue and the
        backend's recording status over local HTTP.
        NEVER use asyncio here — NSRunLoop and asyncio cannot share a loop.
        """
        # Recording state (so the menu stays in sync even when controlled from the web UI)
        try:
            rec = requests.get(f"{APP_URL}/api/recording/status", timeout=1).json()
            self._rec_elapsed = rec.get("elapsed_seconds", 0.0)
            if rec.get("is_recording", False) != self._is_recording:
                self._set_recording(rec.get("is_recording", False))
        except Exception:
            pass

        # Transcription progress (in-process queue from whisper_runner)
        status = _poll_status()
        if status is not None:
            self._txn_running = status.get("running", False)
            self._txn_percent = status.get("percent", 0)

        # Title priority: recording > transcription > idle
        if self._is_recording:
            self.title = f"🔴 {_fmt_elapsed(self._rec_elapsed)}"
        elif self._txn_running:
            self.title = f"⏳ {self._txn_percent}%"
        else:
            self.title = None


if __name__ == "__main__":
    # 1. Start uvicorn in a daemon thread
    threading.Thread(target=_start_uvicorn, daemon=True).start()

    # 2. Wait for backend to be ready
    if not _wait_for_backend():
        rumps.alert(
            title="Whisper Box",
            message="Le backend n'a pas démarré. Vérifiez les logs.",
        )
        sys.exit(1)

    # 3. Open browser (subprocess 'open' — fiable depuis un .app bundle)
    _open_browser(APP_URL)

    # 4. rumps in the MAIN THREAD — this MUST be the last call
    WhisperBoxMenuBar().run()
