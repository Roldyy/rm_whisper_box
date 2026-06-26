# WhisperBox — native macOS app

A native SwiftUI menu-bar + window app: record system/mic audio, transcribe locally
(WhisperKit / Core ML), and optionally summarize with Claude. **Fully isolated** from the
Python/React app — separate build, its own `.app`/`.dmg`. It doesn't touch `app/backend`
or `app/frontend`.

## Features
- **Record** system audio (ScreenCaptureKit) + mic (AVFoundation), system audio optional,
  with pause/resume and a live transcript during recording.
- **Transcribe** dropped/picked files with live streaming progress.
- **Claude enhancement** (summary) via the `claude` CLI, with an editable prompt.
- **History** (in-progress + done), detail sheet, export, on-demand high-quality re-transcribe.
- **Sleep resilience** — prevents idle sleep while busy; finalizes a valid recording on sleep.
- Dark UI matching the design mockups; custom app icon; signed `.dmg` distribution.

## Requirements
- macOS **14.0+** (SwiftData; ScreenCaptureKit audio wants 14.2+).
- **Xcode** (SwiftData macros need the full toolchain, not just CommandLineTools).
- **XcodeGen** (`brew install xcodegen`) — the `.xcodeproj` is generated from `project.yml`.
- Optional: the **`claude` CLI** (`@anthropic-ai/claude-code`) for the summary feature.

## Build & run
```bash
cd whisper-box/app/macos
xcodegen generate          # (re)create WhisperBox.xcodeproj from project.yml
open WhisperBox.xcodeproj  # then Run (⌘R)
```
Re-run `xcodegen generate` whenever files are **added or removed** (the project lists files
at generation time). First launch downloads the WhisperKit Core ML model (one-time, needs
network). Grant **Screen Recording** + **Microphone** on first record.

`swift build` also compiles the sources (handy for quick checks) but doesn't produce the
app bundle / icon — use Xcode or `build-dmg.sh` for that.

## Package a .dmg
```bash
bash build-dmg.sh          # builds Release + makes WhisperBox.dmg (signed, not notarized)
```
See **`PACKAGING.md`** for tester "open" instructions and the notarization (Tier 2) path.

## Structure
```
project.yml                       # XcodeGen spec (bundle id, team, icon, WhisperKit dep)
Package.swift                     # SwiftPM (offline compile-checks; excludes the asset catalog)
build-dmg.sh                      # Release build → signed .dmg
Sources/WhisperBox/
  WhisperBoxApp.swift             # @main App: WindowGroup + MenuBarExtra + ⌘R command
  RootView.swift                  # custom dark shell (sidebar + top bar) + MenuBarView
  Theme.swift / Components.swift  # design tokens + reusable UI (from the mockups)
  Models/Models.swift             # SwiftData: TranscriptionJob, AppSettings
  Services/
    TranscriptionEngine.swift     # protocol + factory (shared singleton) + MockEngine
    WhisperKitEngine.swift        # real engine (actor, cached pipeline)
    LiveTranscriber.swift         # live chunked transcript during recording
    RecordingService.swift        # in-process capture (system+mic), pause/resume, sleep
    RecorderEngine.swift          # WAV writer / mixer / capturers (ported from SCRecorder.swift)
    TranscriptionManager.swift    # app-scoped job owner (progress, persistence, enhancement)
    EnhancementService.swift      # Claude CLI (subscription billing)
    OutputFormatter.swift         # txt / srt / vtt
    KeychainService.swift         # Security.framework (Claude token)
    PowerAssertion.swift          # IOPMAssertion (prevent idle sleep)
  Views/SectionViews.swift        # Record / Transcribe / History (+ detail) / Logs / Settings
  Assets.xcassets/                # app icon
```

## Settled decisions
- Engine: **WhisperKit** (Core ML / ANE, streaming). Model: `openai_whisper-large-v3-v20240930_turbo`, downloaded first-run.
- Persistence: **SwiftData** (greenfield; no import of the old `app.db`).
- Distribution: direct, signed **`.dmg`** (Team `66UL8CW95D`); not Mac App Store, which keeps the Claude CLI / subscription billing.
- Output: transcripts + summaries written to `~/Whisper Memory/transcripts/`; recordings to `~/Whisper Memory/recordings/`.

## Docs
- `SWIFT_MIGRATION_PLAN.md` — full migration plan & phases.
- `UI_REDESIGN_PLAN.md` / `APP_UI_OVERVIEW.md` — design.
- `AUDIT.md` — implementation audit & next steps.
- `PACKAGING.md` — `.dmg` build + distribution.
