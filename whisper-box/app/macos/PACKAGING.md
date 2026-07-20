# Packaging WhisperBox → .dmg

```bash
cd whisper-box/app/macos
bash build-dmg.sh                       # build Release, sign, package, notarize (if configured)
bash build-dmg.sh /path/WhisperBox.app  # package a prebuilt (e.g. Xcode-archived) app, skip the build
```

`build-dmg.sh` signs with your **Developer ID Application** cert (picked from the keychain for
team `U3TUL63HHK`) + **Hardened Runtime** + secure timestamp, then builds `WhisperBox.dmg`.
Manual signing needs no Xcode-logged-in Apple ID / provisioning profile, so it runs headlessly.
The pinned cert keeps a stable identity so **Screen Recording / Microphone TCC grants survive
rebuilds** (ad-hoc `-` signing reset them every build).

## Notarized (no Gatekeeper prompt on any Mac)
Automatic **if** a `notarytool` keychain profile exists — the script submits + staples. Store
credentials once:
```bash
xcrun notarytool store-credentials "WhisperBox-notary" \
  --apple-id <your-apple-id> --team-id U3TUL63HHK \
  --password <app-specific-password>     # appleid.apple.com → App-Specific Passwords
```
(Override the profile name with `NOTARY_PROFILE=…`.) After it runs, verify with
`spctl -a -vvv -t exec <app>` → *accepted / source=Notarized Developer ID*.

## Not notarized (no profile yet) — beta testers click through once
The script still emits a signed `.dmg`. First launch on another Mac:
- **macOS 15:** System Settings → Privacy & Security → scroll down → **Open Anyway**.
- **macOS 13–14:** right-click the app → **Open** → **Open**.
- *"damaged / can't be opened"* (download quarantine):
  ```bash
  xattr -dr com.apple.quarantine /Applications/WhisperBox.app
  ```
Then grant **Screen Recording** (only if system-audio/video capture is used) + **Microphone** on
first record. First transcription downloads the WhisperKit model (needs network, one time).

> **Note:** headless `xcodebuild` can't use a free Personal Team; for an Apple-Development-signed
> build instead of Developer ID, build in the Xcode GUI (`open WhisperBox.xcodeproj` → Run/Archive)
> and pass that `.app` to `build-dmg.sh`.
