#!/bin/bash
# create-app.command — build the macOS .app bundle
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
APP_NAME="WB - Whisper Box"
APP_BUNDLE="$REPO_ROOT/$APP_NAME.app"
APP_VERSION="$(cat "$REPO_ROOT/app/VERSION" | tr -d '[:space:]')"

echo "=== Whisper Box — Create macOS .app ==="
echo "Version : $APP_VERSION"
echo "Bundle  : $APP_BUNDLE"

# --- 1. Find Homebrew Python (3.12 ou 3.11 en priorité — Whisper incompatible 3.13+) ---
PYTHON3=""
for p in \
    /opt/homebrew/bin/python3.12 \
    /opt/homebrew/bin/python3.11 \
    /usr/local/bin/python3.12 \
    /usr/local/bin/python3.11 \
    "$(brew --prefix 2>/dev/null)/bin/python3.12" \
    "$(brew --prefix 2>/dev/null)/bin/python3.11" \
    /opt/homebrew/bin/python3 \
    /usr/local/bin/python3; do
    if [ -x "$p" ]; then
        PYTHON3="$p"
        break
    fi
done

if [ -z "$PYTHON3" ]; then
    echo "ERROR: Python 3 (Homebrew) introuvable."
    exit 1
fi
echo "Python  : $PYTHON3"

# --- 2. Build frontend ---
echo "Build du frontend..."
cd "$REPO_ROOT/app/frontend"
# Supprimer node_modules si installé sur une autre plateforme (Linux → macOS arm64)
if [ -d "node_modules" ]; then
    ROLLUP_ARM="node_modules/@rollup/rollup-darwin-arm64"
    if [ ! -d "$ROLLUP_ARM" ]; then
        echo "  → node_modules incompatibles (autre plateforme détectée) — réinstallation..."
        rm -rf node_modules package-lock.json
    fi
fi
if [ ! -d "node_modules" ]; then npm install; fi
npm run build

# --- 3. Install Python dependencies ---
echo "Installation des dépendances Python..."
# faster-whisper utilise CTranslate2 — pas de pkg_resources, pas de PyTorch requis
"$PYTHON3" -m pip install -r "$REPO_ROOT/app/backend/requirements.txt" --break-system-packages

# --- 4. Create .app structure ---
echo "Création du bundle .app..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy backend source into Resources
cp -r "$REPO_ROOT/app/backend/." "$APP_BUNDLE/Contents/Resources/"

# --- 5. Write shell launcher ---
LAUNCHER="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cat > "$LAUNCHER" << SHELLSCRIPT
#!/bin/bash
cd "\$(dirname "\$0")/../Resources"
exec "$PYTHON3" launcher.py
SHELLSCRIPT
chmod +x "$LAUNCHER"

# --- 6. Copy icon ---
if [ -f "$REPO_ROOT/app/packaging/macos/icon.icns" ]; then
    cp "$REPO_ROOT/app/packaging/macos/icon.icns" "$APP_BUNDLE/Contents/Resources/icon.icns"
fi
# Menu bar icon (PNG) — rumps uses this for the status bar
if [ -f "$REPO_ROOT/app/packaging/macos/icon.png" ]; then
    cp "$REPO_ROOT/app/packaging/macos/icon.png" "$APP_BUNDLE/Contents/Resources/icon.png"
fi

# --- 7. Generate Info.plist from template ---
sed "s/{{VERSION}}/$APP_VERSION/g" \
    "$REPO_ROOT/app/packaging/macos/Info.plist.template" \
    > "$APP_BUNDLE/Contents/Info.plist"

# --- 8. Create Desktop alias ---
DESKTOP_ALIAS="$HOME/Desktop/$APP_NAME.app"
if [ -e "$DESKTOP_ALIAS" ]; then
    rm -f "$DESKTOP_ALIAS"
fi
osascript -e "tell application \"Finder\" to make alias file to POSIX file \"$APP_BUNDLE\" at desktop" 2>/dev/null \
    && echo "Alias créé sur le Bureau : $DESKTOP_ALIAS" \
    || echo "  (alias Bureau non créé — ouvrir manuellement)"

echo ""
echo "✅ Bundle créé : $APP_BUNDLE"
echo "   Double-cliquez sur l'icône du Bureau pour lancer."
echo ""
echo "   Premier lancement : clic droit → Ouvrir → Ouvrir quand même (Gatekeeper)"
