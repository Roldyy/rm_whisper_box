#!/bin/bash
# launch.command — start Whisper Box in dev mode
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=== Whisper Box — Dev Launcher ==="
echo "Répertoire : $REPO_ROOT"

# Find Homebrew Python
PYTHON3=""
for p in \
    "$(brew --prefix 2>/dev/null)/bin/python3" \
    /opt/homebrew/bin/python3 \
    /opt/homebrew/bin/python3.12 \
    /opt/homebrew/bin/python3.11 \
    /usr/local/bin/python3; do
    if [ -x "$p" ]; then
        PYTHON3="$p"
        break
    fi
done

if [ -z "$PYTHON3" ]; then
    echo "ERROR: Python 3 (Homebrew) introuvable. Installez-le via: brew install python"
    exit 1
fi

echo "Python : $PYTHON3"

# Install dependencies
echo "Installation des dépendances..."
"$PYTHON3" -m pip install -r "$REPO_ROOT/app/backend/requirements.txt" --quiet

# Launch
cd "$REPO_ROOT/app/backend"
exec "$PYTHON3" launcher.py
