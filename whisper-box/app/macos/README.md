# WhisperBox — native macOS app

A native SwiftUI menu-bar + window app: record system/mic audio, transcribe locally
(WhisperKit / Core ML), and optionally summarize with Claude. **Fully isolated** from the
Python/React app — separate build, its own `.app`/`.dmg`. It doesn't touch `app/backend`
or `app/frontend`.

## Features
- **Record** system audio (ScreenCaptureKit) + mic (AVFoundation), system audio optional,
  with pause/resume and a **live streaming transcript** during recording — a rolling-window
  transcriber with voice-activity detection and confirmed/unconfirmed segments (ported from
  WhisperKit's `AudioStreamTranscriber` technique, adapted to the mixed system+mic stream).
- **Optional video capture** — record the full screen or a single app's windows alongside the
  audio (Settings → Recording), saved as a separate `.mp4` (H.264) with a "Play video" button
  in History. Audio stays the transcription source; video needs Screen Recording permission.
- **Auto-start on a detected call** — a Core Audio mic-in-use listener spots when Teams, Zoom,
  Webex, Slack, or Discord starts using the microphone and, per Settings (Off / Ask / Auto),
  prompts you or starts recording automatically.
- **Transcribe** dropped/picked files with live streaming progress.
- **Claude enhancement** (summary) via the `claude` CLI, with an editable prompt (default is a
  structured French meeting-synthesis prompt with an AI-warning banner); optional timeout.
- **Push to Odoo Knowledge** — file a meeting summary into your **Private** section of Odoo's
  Knowledge app over the External API (JSON-RPC, API key in Keychain); manual or auto-after-summary.
- **History** (in-progress + done), searchable, full-page detail, export, on-demand
  high-quality re-transcribe, and delete-with-files.
- **Logs (Journaux)** — a persisted event log (info / success / warning / error) with full
  detail, level filter, export, and clear; per-job logs surface in the job detail page.
  Everything is also emitted to the unified log (`os.Logger`, viewable in Console.app).
- **Durable recording** — records to a local staging dir then moves the finalized file into the
  output folder (safe with cloud-sync folders); crash-safe WAV header rewrites; quit-while-
  recording finalizes the file; a stalled capture source is detected and dropped.
- **Cloud output** — point the output folder at a OneDrive/iCloud sync root (Settings →
  Output folder → "Cloud…" one-tap shortcuts) and recordings/transcripts sync automatically.
- **Sleep resilience** — prevents idle sleep while busy; finalizes a valid recording on sleep.
- Dark UI matching the design mockups; custom app icon; signed `.dmg` distribution.

## Requirements
- macOS **14.0+** (SwiftData; ScreenCaptureKit audio wants 14.2+).
- **Xcode** (SwiftData macros need the full toolchain, not just CommandLineTools).
- **XcodeGen** (`brew install xcodegen`) — the `.xcodeproj` is generated from `project.yml`.
- Optional: the **`claude` CLI** (`@anthropic-ai/claude-code`) for the summary feature.
- Optional: an **Odoo** instance with Enterprise/Online **Knowledge** and External API access
  (Custom plan) + an API key, for the "Push to Odoo Knowledge" feature.

## Build & run
```bash
cd whisper-box/app/macos
xcodegen generate          # (re)create WhisperBox.xcodeproj from project.yml
open WhisperBox.xcodeproj  # then Run (⌘R)
```
Re-run `xcodegen generate` whenever files are **added or removed** (the project lists files
at generation time). First launch downloads the WhisperKit Core ML model (one-time, needs
network). Grant **Microphone** on first record; **Screen Recording** is only requested when
system-audio or video capture is enabled.

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
  WindowConfigurator.swift        # native window behavior (drag/zoom/resize) under custom chrome
  Theme.swift / Components.swift  # design tokens + reusable UI (from the mockups)
  Models/Models.swift             # SwiftData: TranscriptionJob, AppSettings, ExecutionLog
  Services/
    TranscriptionEngine.swift     # protocol + factory (shared singleton) + MockEngine
    WhisperKitEngine.swift        # real engine (actor, cached pipeline)
    LiveTranscriber.swift         # rolling-window live transcript (VAD + confirmed/unconfirmed)
    RecordingService.swift        # in-process capture (system+mic+video), pause/resume, sleep, staging→output move
    RecorderEngine.swift          # WAV writer / mixer (stall guard) / audio+video capturers
    CallDetector.swift            # Core Audio mic-in-use listener → auto-start signal
    TranscriptionManager.swift    # app-scoped job owner (progress, persistence, enhancement, Odoo push)
    EnhancementService.swift      # Claude CLI (subscription billing; timeout + stderr capture)
    OdooService.swift             # Odoo Knowledge push (JSON-RPC External API)
    Log.swift                     # os.Logger facade + persisted ExecutionLog (feeds the Logs tab)
    AppPaths.swift                # transcripts/recordings dirs (configurable base) + local staging + cloud providers
    OutputFormatter.swift         # txt / srt / vtt
    KeychainService.swift         # Security.framework (Claude token + Odoo API key)
    PowerAssertion.swift          # IOPMAssertion (prevent idle sleep)
  Views/SectionViews.swift        # Record / Transcribe / History (+ detail) / Logs / Settings
  Assets.xcassets/                # app icon
```

## Settled decisions
- Engine: **WhisperKit** (Core ML / ANE, streaming). Model: `openai_whisper-large-v3-v20240930_turbo`, downloaded first-run.
- Persistence: **SwiftData** (greenfield; no import of the old `app.db`).
- Distribution: direct, signed **`.dmg`** (Team `U3TUL63HHK`); not Mac App Store, which keeps the Claude CLI / subscription billing.
- Output: transcripts + summaries and recordings are written under a configurable base
  directory (Settings → Output folder), **defaulting to `~/Whisper Memory/`** (`transcripts/`
  + `recordings/` subfolders).

## Docs
- `CLAUDE.md` — working notes (build/run/test, gotchas, conventions).
- `AUDIT.md` — implementation audit, backlog & next steps.
- `TESTING.md` — test coverage status & gaps.
- `PACKAGING.md` — `.dmg` build + notarization.
