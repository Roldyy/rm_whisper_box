"""
api/system.py — System-level helpers (native file picker, etc.)
"""

import asyncio

from fastapi import APIRouter

router = APIRouter(prefix="/api", tags=["system"])

# `choose file` is a StandardAdditions command osascript runs itself — no
# "System Events" dependency, so it needs no Automation (TCC) permission.
# Run inside a `try` so cancelling the dialog yields a clean empty result
# instead of a non-zero exit.
_OSASCRIPT = [
    "osascript", "-e",
    (
        'try\n'
        '  POSIX path of (choose file with prompt "Choisir un fichier audio ou vidéo")\n'
        'on error number -128\n'  # user cancelled
        '  return ""\n'
        'end try'
    ),
]


@router.get("/pick-file")
async def pick_file():
    """Open native macOS file picker dialog and return the selected path."""
    proc = await asyncio.create_subprocess_exec(
        *_OSASCRIPT,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    stdout, _ = await proc.communicate()
    if proc.returncode == 0:
        return {"path": stdout.decode().strip()}
    # User cancelled or error — return null path
    return {"path": None}
