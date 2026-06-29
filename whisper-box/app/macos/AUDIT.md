# WhisperBox (native macOS) — Implementation Audit

Snapshot of the Swift app: **cleanly layered, building green.** Purpose: track health
and next steps. _Last updated: 2026-06-29 — logging (#18), configurable output dirs (#17),
native window controls (#20), and English UI (#21) landed; live transcriber reworked
(rolling buffer + VAD + confirmed/unconfirmed, ported from WhisperKit's AudioStreamTranscriber);
redundant Claude auto-summarize toggle merged into one._

## Résumé — what's built
- **Architecture:** app-scoped `@Observable` services (`TranscriptionManager`, `RecordingService`)
  so state survives navigation; a **shared engine singleton** (one model in memory);
  clean Services / Views / Models / Theme split.
- **Features:** file transcription with live progress; in-process recording (system + mic,
  system audio optional, pause/resume); live transcript; Claude enhancement (editable
  prompt); History (sections + full-page detail + export + re-transcribe); Logs; Settings;
  sleep resilience (power assertion + graceful finalize); custom dark UI matching the
  mockups; app icon; signed `.dmg` path (`build-dmg.sh`).
- **Portable in concept:** engine, formatters, job model — clean for any future
  cross-platform move (whisper.cpp core).

## Findings

### 🔴 Correctness / UX — ✅ resolved
1. ✅ **Model-download feedback** — first run shows "Préparation du modèle…" + indeterminate
   bar (`prewarm()` before transcribe + `preparingModel` flag).
2. ✅ **⌘R** — real app command + keyboard shortcut (toggles record/stop app-wide).
3. ✅ **Cancellation** — WhisperKit callback returns `!Task.isCancelled`; `run()` marks the
   job cancelled rather than success.
4. ✅ **Language setting** — Settings "Langue" picker, wired into file + live transcription.

### 🟡 Tech debt — ✅ mostly resolved
5. ✅ **`ChunkedTranscriber` / `ChunkPlanner` removed** (were unused).
6. ✅ **`ExecutionLog` removed** (model was never written).
7. ⚠️ **Partially:** `defaultLanguage` now wired; `defaultModel` is still hardcoded
   (`large-v3-turbo`, intentional — model is locked in the UI) and `defaultOutputDir`
   is unused (output now goes to a fixed transcripts dir, see #8).
8. ✅ **Output location** — transcripts/summaries now write to `~/Whisper Memory/transcripts/`.

### 🟢 Deferred features / polish — open
9.  History **search field** (in mockup, not built).
10. ✅ **Audio duration** — `durationAudio` is set on completion (from the last segment's
    end time) and shown in the History detail header. Older jobs stay blank.
11. **Menu-bar red glyph** while recording (currently shows elapsed time; needs a custom
    non-template image).
12. **Transcription sleep-checkpoint** (plan §10.3 Path A) — forced sleep mid-transcription
    still interrupts it (recording is handled).
13. ✅ **`claude` CLI presence** — Settings shows detected/introuvable; enhancement fails
    fast with a clear message if missing.

### 🔵 Infra — open
14. **No tests** — pure-logic services (`OutputFormatter`) are trivially unit-testable;
    add an XCTest target.
15. **Swift 5 language mode** — Swift 6 strict concurrency would surface a few `@Sendable`
    issues (currently fine).
16. **Notarization** (Tier 2) for distribution beyond a few beta testers.
17. ✅ **Configurable output directories** — `AppPaths` (`Services/AppPaths.swift`) resolves
    transcripts/summaries + recordings from a configurable base, **defaulting to the original
    `~/Whisper Memory`** when unset. Wired `AppSettings.defaultOutputDir` to a folder picker in
    Settings (seeded at launch in `RootView.onAppear`, live-updated on pick). Recording
    detection no longer hardcodes the path (`AppPaths.isRecording(path:)`).
18. ✅ **Real logging** — `Log` facade over `os.Logger` + persisted `ExecutionLog`
    (`Services/Log.swift`, `Models.swift`): levels info/success/warning/error, optional
    `job` relationship with `.cascade` delete. Rebuilt the "Journaux" tab (filter, detail
    sheet, Export, Clear) and added a per-job "Journaux" tab in `JobDetailView`. Launch-time
    prune (14 days / 2000 cap). Key failure + success sites instrumented (recording,
    transcription, enhancement).

### 🟣 UX / feature — open
19. **Global recording shortcuts (configurable)** — today the record toggle (⌘R) is an
    in-app command (`WhisperBoxApp.swift:33–46`), so it only fires when the app is focused.
    Add two **system-wide** hotkeys that work unfocused:
    - **Start/stop toggle** — one combo that starts when idle and stops when recording/paused
      (same logic as ⌘R: `recorder.start(captureSystem:captureMic:)` / `stopAndTranscribe()`).
    - **Pause/resume toggle** — a separate combo toggling `recorder.pause()` / `resume()`.
    Both **user-configurable** in Settings (defaults TBD, e.g. ⌘⌥R / ⌘⌥P). Carbon
    `RegisterEventHotKey` needs no extra entitlements (app is unsandboxed); or use a small
    lib (e.g. `KeyboardShortcuts`) for storage + a recorder field. Complements the MenuBarExtra.
20. ✅ **Native window controls for the chrome** — minimal fix landed: kept the custom dark
    `Theme`, added `WindowConfigurator` (`WindowConfigurator.swift`) that sets
    `isMovableByWindowBackground` + a transparent full-size-content title bar, so drag-to-move,
    double-click-to-zoom, and resize work again. _Deferred alternative (not done):_ full native
    `NavigationSplitView` + `.toolbar`, which would force a light/dark theming project.
21. ✅ **English UI** — all user-facing strings translated French → English (straight
    replacement, option a) across views, services, log/error messages, and the Info.plist mic
    usage string in `project.yml`. UI language remains separate from the transcription
    `defaultLanguage` and the Claude prompt.

## Remaining next steps
- Polish: History search (#9), menu-bar red glyph (#11).
- UX: global recording shortcuts (#19) — still open.
- Robustness: transcription sleep-checkpoint (#12), test target (#14).
- Distribution: notarization (#16) when going beyond beta testers.
- Tidy: drop the unused `defaultModel` setting (#7).
