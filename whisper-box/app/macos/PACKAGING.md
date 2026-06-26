# Packaging WhisperBox → .dmg

## Tier 1 — ad-hoc signed, not notarized — for you + beta testers

Build the `.dmg`:
```bash
cd whisper-box/app/macos
bash build-dmg.sh
```
Produces `WhisperBox.dmg` (app + Applications drag-target), **ad-hoc signed** (`-`) — no
Apple account/team/profile needed, so it builds headlessly. Fine for a beta.

> **Team-signed build (more stable TCC):** headless `xcodebuild` can't use a free Personal
> Team account, so for an Apple-Development-signed build, **build in the Xcode GUI** instead
> (`open WhisperBox.xcodeproj` → Run/Archive — `project.yml` keeps Team `66UL8CW95D`), then
> package that `.app`. The script stays ad-hoc on purpose.

### What a beta tester does on first launch
The app isn't notarized, so macOS shows a Gatekeeper warning once. To open:
- **macOS 15 (Sequoia):** System Settings → Privacy & Security → scroll down → **Open Anyway**.
- **macOS 13–14:** right-click the app → **Open** → **Open**.
- If it says *“damaged / can’t be opened”* (quarantine on a downloaded dmg):
  ```bash
  xattr -dr com.apple.quarantine /Applications/WhisperBox.app
  ```
Then grant **Screen Recording** + **Microphone** permissions on first record.
First transcription downloads the WhisperKit model (needs network, one time).

## Tier 2 — notarized (no warnings, for anyone) — needs paid Apple Developer Program
After enrolling ($99/yr) and installing a **Developer ID Application** cert:
1. Sign with Developer ID + hardened runtime (add `ENABLE_HARDENED_RUNTIME: YES` and an
   entitlements file to `project.yml`).
2. `xcrun notarytool submit WhisperBox.dmg --apple-id <id> --team-id 66UL8CW95D --password <app-specific-pw> --wait`
3. `xcrun stapler staple WhisperBox.dmg`
Then it opens with no Gatekeeper prompt on any Mac.
