# services/status_bridge.py
# Thread-safe bridge between asyncio (whisper_runner) and rumps (main thread).
# Uses queue.Queue — never asyncio.Queue — because NSRunLoop and asyncio
# cannot share a queue directly.
import queue

_bridge: queue.Queue = queue.Queue(maxsize=10)


def push(running: bool, percent: int = 0):
    """Push a status update from whisper_runner to the menu bar."""
    try:
        _bridge.put_nowait({"running": running, "percent": percent})
    except queue.Full:
        pass  # drop silently if queue is full


def poll():
    """Poll the latest status — called from rumps @timer (main thread)."""
    try:
        return _bridge.get_nowait()
    except queue.Empty:
        return None
