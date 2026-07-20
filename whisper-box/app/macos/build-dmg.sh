#!/bin/bash
# Build a Tier-1 (signed with your Apple Development cert, not notarized) .dmg.
# Good for yourself + beta testers who can click through Gatekeeper once.
set -e
cd "$(dirname "$0")"

APP_NAME="WhisperBox"
CONFIG="Release"
DERIVED="build"
TEAM_ID="U3TUL63HHK"        # Apple Developer team; must match project.yml DEVELOPMENT_TEAM

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
  # Sign manually with the Developer ID Application cert — required for notarized
  # distribution outside the App Store. Manual signing needs no Xcode-logged-in Apple ID
  # or provisioning profile (the mic entitlement is a Hardened Runtime entitlement, not a
  # profile-gated capability), so it works headlessly. Pinning the exact SHA-1 hash forces
  # the same cert onto the SPM dependency targets and keeps a stable identity, so Screen
  # Recording / Microphone TCC grants survive rebuilds (ad-hoc "-" resets them each build).
  # Select the Developer ID Application cert for THIS team specifically — the keychain may
  # hold certs for several teams (identity string ends in "(<TEAM_ID>)").
  SIGN_ID=$(security find-identity -v -p codesigning | awk -v t="($TEAM_ID)" '/Developer ID Application/ && index($0, t) {print $2; exit}')
  [ -n "$SIGN_ID" ] || { echo "✗ No 'Developer ID Application' identity for team $TEAM_ID in keychain. Import the cert (.p12 or .cer) first."; exit 1; }
  echo "▸ Building $CONFIG (Developer ID signed: $SIGN_ID)…"
  set +e
  # --timestamp: a secure timestamp is mandatory for notarization.
  # Hardened Runtime + entitlements come from project.yml (ENABLE_HARDENED_RUNTIME,
  # CODE_SIGN_ENTITLEMENTS).
  xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" \
    -configuration "$CONFIG" -derivedDataPath "$DERIVED" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$SIGN_ID" \
    DEVELOPMENT_TEAM="$TEAM_ID" PROVISIONING_PROFILE_SPECIFIER="" \
    OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
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

# ── Notarize + staple ──────────────────────────────────────────────────────────
# Requires notarytool credentials stored once under a keychain profile:
#   xcrun notarytool store-credentials "$NOTARY_PROFILE" \
#     --apple-id <your-apple-id> --team-id U3TUL63HHK \
#     --password <app-specific-password>   # from appleid.apple.com → App-Specific Passwords
# Set NOTARY_PROFILE (default below) to skip/enable this step.
NOTARY_PROFILE="${NOTARY_PROFILE:-WhisperBox-notary}"
if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "▸ Notarizing (profile: $NOTARY_PROFILE)… this can take a few minutes."
  if xcrun notarytool submit "$APP_NAME.dmg" --keychain-profile "$NOTARY_PROFILE" --wait; then
    xcrun stapler staple "$APP_NAME.dmg"
    echo "✓ Notarized + stapled — opens cleanly on any Mac (no Gatekeeper prompt)."
    # Verify the built app itself (not the DMG): a stapled/notarized DMG isn't
    # code-signed, so assessing the DMG with primary-signature falsely says
    # "no usable signature". The meaningful check is Gatekeeper's exec assessment
    # of the app → "accepted / source=Notarized Developer ID".
    spctl -a -vvv -t exec "$APP" 2>&1 | sed 's/^/  /' || true
  else
    echo "✗ Notarization failed. Inspect with:"
    echo "    xcrun notarytool log <submission-id> --keychain-profile $NOTARY_PROFILE"
    exit 1
  fi
else
  echo "  Signed by: $(codesign -dvv "$APP" 2>&1 | grep -E 'Authority=|Signature=' | head -1 | sed 's/^ *//')"
  echo "  ⚠ Not notarized — no '$NOTARY_PROFILE' notarytool profile found."
  echo "    Store credentials once (see comment in build-dmg.sh), then re-run to notarize."
  echo "    Until then, testers must approve via System Settings → Privacy & Security → Open Anyway."
fi
