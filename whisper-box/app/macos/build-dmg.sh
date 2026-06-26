#!/bin/bash
# Build a Tier-1 (signed with your Apple Development cert, not notarized) .dmg.
# Good for yourself + beta testers who can click through Gatekeeper once.
set -e
cd "$(dirname "$0")"

APP_NAME="WhisperBox"
CONFIG="Release"
DERIVED="build"

echo "▸ Generating project…"
xcodegen generate

echo "▸ Building $CONFIG…"
xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" \
  -configuration "$CONFIG" -derivedDataPath "$DERIVED" \
  build | tail -5

APP="$DERIVED/Build/Products/$CONFIG/$APP_NAME.app"
[ -d "$APP" ] || { echo "✗ App not found at $APP"; exit 1; }

echo "▸ Packaging .dmg…"
STAGE="dmg-stage"
rm -rf "$STAGE" "$APP_NAME.dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"      # drag-to-install
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$APP_NAME.dmg" >/dev/null
rm -rf "$STAGE"

echo "✓ Created $(pwd)/$APP_NAME.dmg"
echo "  Signed with: $(codesign -dvv "$APP" 2>&1 | grep 'Authority=Apple Development' | head -1)"
