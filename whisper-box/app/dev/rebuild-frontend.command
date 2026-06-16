#!/bin/bash
# rebuild-frontend.command — rebuild React frontend and copy to backend/static
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FRONTEND_DIR="$REPO_ROOT/app/frontend"

echo "=== Whisper Box — Rebuild Frontend ==="

if [ ! -d "$FRONTEND_DIR" ]; then
    echo "ERROR: Répertoire frontend introuvable : $FRONTEND_DIR"
    exit 1
fi

cd "$FRONTEND_DIR"

# Install npm deps if needed
if [ ! -d "node_modules" ]; then
    echo "Installation des dépendances npm..."
    npm install
fi

echo "Build du frontend..."
npm run build

echo "Frontend construit dans : $REPO_ROOT/app/backend/static"
