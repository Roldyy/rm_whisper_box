#!/bin/bash
# Build a Tier-1 (signed with your Apple Development cert, not notarized) .dmg.
# Good for yourself + beta testers who can click through Gatekeeper once.
set -e
cd "$(dirname "$0")"

APP_NAME="WhisperBox"
CONFIG="Release"
DERIVED="build"

# Usage:
#   ./build-dmg.sh                  → ad-hoc build headlessly, then package
#   ./build-dmg.sh /path/WhisperBox.app → package a prebuilt (e.g. Xcode-archived,
#                                          team-signed) app — skips the build
if [ -n "$1" ] && [ -d "$1" ]; then
  APP="$1"
  echo "▸ Packaging provided app: $APP"
else
  echo "▸ Generating project…"
  xcodegen generate
  echo "▸ Building $CONFIG (ad-hoc signed)…"
  # Ad-hoc ("-") needs no Apple account/team/profile → works headlessly (fine for beta).
  # For a team-signed build (stable TCC), Archive in the Xcode GUI and pass its .app here.
  xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" \
    -configuration "$CONFIG" -derivedDataPath "$DERIVED" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER="" \
    build 2>&1 | grep -iE "error:|BUILD (SUCCEEDED|FAILED)" || true
  APP="$DERIVED/Build/Products/$CONFIG/$APP_NAME.app"
fi

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
echo "  Signed by: $(codesign -dvv "$APP" 2>&1 | grep -E 'Authority=|Signature=' | head -1 | sed 's/^ *//')"
echo "  (Not notarized → testers approve once via 'Open Anyway' on first launch.)"
