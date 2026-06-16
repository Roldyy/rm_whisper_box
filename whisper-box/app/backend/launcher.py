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
        self.menu = [
            rumps.MenuItem("Ouvrir Whisper Box", callback=self._open),
            None,
            rumps.MenuItem("Quitter", callback=lambda _: rumps.quit_application()),
        ]

    def _open(self, _):
        _open_browser(APP_URL)

    @rumps.timer(2)
    def _poll_status(self, _):
        """
        Runs in the main thread — reads queue.Queue from status_bridge.
        NEVER use asyncio here — NSRunLoop and asyncio cannot share a loop.
        """
        status = _poll_status()
        if status is not None:
            if status.get("running"):
                self.title = f"⏳ {status['percent']}%"
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
