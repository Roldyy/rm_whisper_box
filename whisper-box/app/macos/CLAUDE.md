# WhisperBox (native macOS) — working notes for Claude

Native SwiftUI **menu-bar + window** app: record system/mic audio (+ optional video),
transcribe locally with **WhisperKit** (Core ML/ANE), optionally summarize via the **Claude
CLI**, and push notes to **Odoo Knowledge**. Fully isolated from the repo's Python/React app —
its own build and `.app`/`.dmg`. Everything here lives under `whisper-box/app/macos`.

## Build / run / test
```bash
cd whisper-box/app/macos
swift build                 # fast compile-check of Sources/WhisperBox (NO app bundle, NO icon)
swift test                  # run the unit tests (Tests/WhisperBoxTests) — pure-logic only
xcodegen generate           # (re)generate WhisperBox.xcodeproj from project.yml
open WhisperBox.xcodeproj    # then Run (⌘R) — needed for the real app bundle + TCC permissions
bash build-dmg.sh            # Release → Developer ID-signed .dmg (+ notarize/staple if a profile exists)
```
- **`swift build` green ≠ verified.** It compiles but produces no bundle. Recording, call
  detection, video, and TCC-gated paths (Screen Recording / Microphone) only work from the
  **signed app bundle** — run in Xcode or via `build-dmg.sh`. There is no headless way to
  exercise those; say so rather than implying runtime coverage.
- **Re-run `xcodegen generate` whenever files are added/removed** (project.yml lists files at
  generation time). `swift test` and `swift build` do NOT need it.
- Requires **Xcode** (SwiftData macros need the full toolchain), macOS **14.0+** target.

## Architecture (Sources/WhisperBox)
- App-scoped `@Observable` services injected via `.environment`, so state survives navigation:
  `TranscriptionManager` (job owner: progress, persistence, enhancement, Odoo push),
  `RecordingService` (capture orchestration), `CallDetector` (auto-start signal).
- `Services/` = engine (`WhisperKitEngine` actor + `MockEngine`), `LiveTranscriber` (rolling-window
  live transcript), `RecorderEngine` (WAV writer / `AudioMixer` / audio+video capturers),
  `EnhancementService` (claude CLI), `OdooService` (JSON-RPC), `AppPaths`, `Log`, `OutputFormatter`,
  `KeychainService`, `PowerAssertion`.
- `Models/Models.swift` = SwiftData: `TranscriptionJob`, `AppSettings`, `ExecutionLog`.
- `Views/SectionViews.swift` = Record / Transcribe / History / Logs / Settings. `RootView.swift` =
  custom dark shell + MenuBarView. `WhisperBoxApp.swift` = `@main` + `AppDelegate`.

## Gotchas that bite
- **Unsandboxed** (shells out to `claude`, uses ScreenCaptureKit). Only entitlement is mic
  (`WhisperBox.entitlements`); Hardened Runtime is on for notarization.
- **Swift 5 language mode** (project.yml `SWIFT_VERSION: 5.0`); Swift 6 strict concurrency would
  surface a few `@Sendable`/isolation issues. Keep concurrency correct anyway — this app has
  real `@MainActor` reentrancy-across-`await`, unstructured `Task`s, `AsyncStream`, `NSLock`, and
  a CoreAudio listener. Watch those.
- Recording writes to a **local staging dir** then moves the finalized file into the (possibly
  cloud-synced) output dir — never write a growing file into OneDrive/iCloud.
- Model is locked to `openai_whisper-large-v3-v20240930_turbo`; Claude model is an alias
  (opus/sonnet/haiku) resolved by the CLI. Default output base is `~/Whisper Memory` (configurable).
- SIGPIPE is ignored at launch (AppDelegate) — a claude CLI that exits early must not crash us.

## Conventions
- Match surrounding comment density/idiom. Reference audit items as `#NN` in comments/commits.
- UI copy is **English**; the default Claude prompt is **French** (meeting synthesis). Code +
  identifiers are English.
- When Anthropic/Claude model facts are involved, load the `claude-api` skill — don't answer from memory.

## Workflow that's been working
Opus writes; a **fable** subagent reviews (`/code-review`, or delegated with `model: fable`).
The two-model loop has repeatedly caught bugs the writer missed — keep using it for non-trivial changes.

## Docs
- `README.md` — user/dev overview.  `AUDIT.md` — current health, backlog (`#NN` findings), next steps.
- `TESTING.md` — coverage status + prioritized gaps.  `PACKAGING.md` — `.dmg` build + notarization.
- Git history holds the change log; don't turn AUDIT into a changelog.
