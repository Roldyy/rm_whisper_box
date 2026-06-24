"""keychain.py — macOS Keychain wrapper for the Claude OAuth token."""

import os
import subprocess

_SERVICE = "whisperbox-claude-oauth"
_BINARY = "/usr/bin/security"


def set_token(value: str) -> None:
    """Store the OAuth token in macOS Keychain (upsert via -U flag)."""
    subprocess.run(
        [
            _BINARY, "add-generic-password",
            "-a", os.environ.get("USER", ""),
            "-s", _SERVICE,
            "-w", value,
            "-U",
        ],
        capture_output=True,
        check=True,
    )


def get_token() -> str | None:
    """Read the OAuth token from macOS Keychain. Returns None if absent."""
    try:
        r = subprocess.run(
            [
                _BINARY, "find-generic-password",
                "-a", os.environ.get("USER", ""),
                "-s", _SERVICE,
                "-w",
            ],
            capture_output=True,
            text=True,
        )
        if r.returncode == 0:
            return r.stdout.strip() or None
        return None
    except Exception:
        return None


def delete_token() -> None:
    """Remove the OAuth token from macOS Keychain (no-op if absent)."""
    subprocess.run(
        [_BINARY, "delete-generic-password", "-s", _SERVICE],
        capture_output=True,
    )
