#!/bin/bash
# make-icns.command — Convert icon.png to icon.icns using iconutil (macOS only)
# Run this on the real macOS machine after modifying icon.png.
# Requires: sips (built-in) and iconutil (built-in on macOS)
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PACKAGING_DIR="$REPO_ROOT/app/packaging/macos"
SOURCE_PNG="$PACKAGING_DIR/icon.png"
ICONSET="$PACKAGING_DIR/icon.iconset"
OUTPUT_ICNS="$PACKAGING_DIR/icon.icns"

echo "=== Whisper Box — Generate icon.icns ==="
echo "Source : $SOURCE_PNG"

if [ ! -f "$SOURCE_PNG" ]; then
    echo "ERROR: icon.png introuvable : $SOURCE_PNG"
    exit 1
fi

# Create iconset directory
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

# Generate all required sizes using sips
for SIZE in 16 32 64 128 256 512; do
    sips -z $SIZE $SIZE "$SOURCE_PNG" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" > /dev/null 2>&1
    DOUBLE=$((SIZE * 2))
    sips -z $DOUBLE $DOUBLE "$SOURCE_PNG" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" > /dev/null 2>&1
done

# Convert iconset to icns
iconutil -c icns "$ICONSET" -o "$OUTPUT_ICNS"

# Cleanup
rm -rf "$ICONSET"

echo "icon.icns créé : $OUTPUT_ICNS"
file "$OUTPUT_ICNS"
