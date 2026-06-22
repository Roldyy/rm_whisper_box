"""
recording_service.py — manages the SCRecorder subprocess lifecycle.

SCRecorder is a compiled Swift binary at Contents/Resources/SCRecorder.
It captures system audio and, on --mic, the microphone too, mixing both
into the single output WAV. This service just returns that file once the
recorder has finalized it.
"""

import asyncio
import subprocess
import time
from pathlib import Path
from typing import Optional


class RecordingService:
    def __init__(self):
        self._process: Optional[subprocess.Popen] = None
        self._output_path: Optional[Path] = None
        self._capture_mic: bool = False
        self._start_time: Optional[float] = None
        self._lock = asyncio.Lock()

    @property
    def is_recording(self) -> bool:
        return self._process is not None and self._process.poll() is None

    @property
    def elapsed_seconds(self) -> float:
        if self._start_time is None:
            return 0.0
        return time.monotonic() - self._start_time

    def _binary_path(self) -> Path:
        candidates = [
            # .app bundle: Resources/SCRecorder next to the backend package root
            Path(__file__).parent.parent / "SCRecorder",
            # Dev mode: compiled binary next to the Swift source
            Path(__file__).parent.parent.parent / "swift" / "SCRecorder",
        ]
        for c in candidates:
            if c.exists():
                return c
        raise FileNotFoundError(
            "SCRecorder binary not found. Build it via create-app.command "
            "(compiles to app/swift/SCRecorder for dev use)."
        )

    async def start(self, output_path: Path, capture_mic: bool = False) -> None:
        async with self._lock:
            if self.is_recording:
                raise RuntimeError("Already recording")

            binary = self._binary_path()
            cmd = [str(binary), "--output", str(output_path)]
            if capture_mic:
                cmd.append("--mic")

            self._process = subprocess.Popen(
                cmd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
            )
            self._output_path = output_path
            self._capture_mic = capture_mic
            self._start_time = time.monotonic()

    async def stop(self) -> Optional[Path]:
        async with self._lock:
            if not self.is_recording:
                return None

            process = self._process
            output_path = self._output_path

            # SIGTERM → Swift mixes/finalizes the WAV header and exits
            process.terminate()
            try:
                process.wait(timeout=8)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()

            self._process = None
            self._start_time = None
            self._output_path = None
            self._capture_mic = False

            if output_path is None or not output_path.exists():
                return None

            # SCRecorder already mixed mic + system audio into this one file.
            return output_path


# Module-level singleton
recording_service = RecordingService()
