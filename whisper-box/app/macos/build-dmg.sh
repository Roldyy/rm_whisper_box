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
  # Sign manually with the Apple Development cert in the keychain, pinned by its exact
  # SHA-1 hash. Manual signing needs no Xcode-logged-in Apple ID or provisioning profile
  # (this app has no profile-gated entitlements), so it works headlessly — unlike
  # Automatic. The hash is resolved at build time so it survives yearly cert rotation;
  # pinning it (vs. the generic "Apple Development" name) stops xcodebuild from falling
  # back to a nonexistent "Mac Development" identity, and forces the same cert onto the
  # SPM dependency targets. A stable identity keeps Screen Recording / Microphone grants
  # across rebuilds; ad-hoc ("-") changes the cdhash every build and resets them.
  SIGN_ID=$(security find-identity -v -p codesigning | awk '/Apple Development/ {print $2; exit}')
  [ -n "$SIGN_ID" ] || { echo "✗ No 'Apple Development' signing identity in keychain (security find-identity)."; exit 1; }
  echo "▸ Building $CONFIG (signed with $SIGN_ID for stable TCC permissions)…"
  set +e
  xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" \
    -configuration "$CONFIG" -derivedDataPath "$DERIVED" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$SIGN_ID" \
    DEVELOPMENT_TEAM=66UL8CW95D PROVISIONING_PROFILE_SPECIFIER="" \
    build 2>&1 | grep -iE "error:|BUILD (SUCCEEDED|FAILED)"
  build_status=${PIPESTATUS[0]}
  set -e
  [ "$build_status" -eq 0 ] || { echo "✗ Build failed — not packaging (would otherwise ship a stale app)."; exit 1; }
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
