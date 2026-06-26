# WhisperBox — native macOS app (Phase 1 skeleton)

Native SwiftUI rewrite, **fully isolated** from the Python/React app: separate build,
its own `.app`/`.dmg`. It does not touch `app/backend` or `app/frontend`; the only thing
it reuses from the repo is `app/swift/SCRecorder.swift` (ported in-process in Phase 3).

See `../SWIFT_MIGRATION_PLAN.md` for the full plan; this directory is **Phase 1**.

## Status

| Layer | Builds offline (CommandLineTools)? |
|---|---|
| Portable core — services/engine/keychain (`Services/`) | ✅ `swiftc -typecheck` passes |
| App layer — SwiftUI + SwiftData (`@main`, `@Model`, `@Query`, Views) | ❌ needs **full Xcode** |

The app layer can't compile under bare CommandLineTools because SwiftData's macro plugin
(`SwiftDataMacros`, backing `@Model`/`@Query`) **ships with Xcode, not the CLT**. Install
Xcode, then it builds.

## Structure

```
Package.swift                     # SwiftPM (macOS 14). WhisperKit dep commented until Xcode.
Sources/WhisperBox/
  WhisperBoxApp.swift             # @main App: WindowGroup + MenuBarExtra + ModelContainer
  RootView.swift                  # NavigationSplitView shell (Record/Transcribe/History/Logs/Settings) + MenuBarView
  Models/Models.swift             # SwiftData @Model: TranscriptionJob, ExecutionLog, AppSettings (+ §10.4 pause/sleep fields)
  Services/
    TranscriptionEngine.swift     # protocol + TranscriptSegment + factory + MockEngine (offline)
    WhisperKitEngine.swift        # real engine, gated on #if canImport(WhisperKit)
    RecordingService.swift        # @Observable state machine + pause/resume + sleep hooks (§10)
    EnhancementService.swift      # Claude CLI via Process (subscription billing, port of claude_runner.py)
    KeychainService.swift         # Security.framework (replaces /usr/bin/security)
  Views/SectionViews.swift        # the five sections (Phase-1 placeholders)
```

## Build (once Xcode is installed)

1. Add WhisperKit: in Xcode, **File ▸ Add Package Dependencies** → `https://github.com/argmaxinc/WhisperKit.git`
   (or uncomment the dependency + product in `Package.swift`).
2. `WhisperKitEngine.swift` lights up automatically (it's behind `#if canImport(WhisperKit)`);
   `TranscriptionEngineFactory.make()` then returns it instead of `MockEngine`.
3. Build & run. First launch downloads the Core ML model (`openai_whisper-large-v3-v20240930_turbo`).

For distribution (later): add an app target with entitlements (audio input, screen recording
for ScreenCaptureKit), hardened runtime, codesign + notarize, package `.dmg`.

## Decisions baked in
- Engine: **WhisperKit** (Core ML / ANE, built-in streaming).
- Persistence: **SwiftData** (greenfield, no import of the old `app.db`).
- Distribution: direct **`.dmg`** (not Mac App Store → keeps the Claude CLI / subscription billing).
- Model: downloaded **first-run** (with a progress UI to be added), full-precision turbo for French.

## Assumptions to confirm
- Minimum macOS: **14.0** (SwiftData; ScreenCaptureKit audio wants 14.2+).
- Bundle id / display name: TBD (e.g. `be.squareflow.whisperbox` / "WhisperBox").
