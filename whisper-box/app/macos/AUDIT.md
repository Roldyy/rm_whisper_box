# WhisperBox (native macOS) — Implementation Audit

Snapshot of the Swift app: **cleanly layered, building green.** Purpose: track health
and next steps. _Last updated: 2026-06-26 — logging layer (#18) landed; live transcriber
reworked (rolling buffer + VAD + confirmed/unconfirmed, ported from WhisperKit's
AudioStreamTranscriber)._

## Résumé — what's built
- **Architecture:** app-scoped `@Observable` services (`TranscriptionManager`, `RecordingService`)
  so state survives navigation; a **shared engine singleton** (one model in memory);
  clean Services / Views / Models / Theme split.
- **Features:** file transcription with live progress; in-process recording (system + mic,
  system audio optional, pause/resume); live transcript; Claude enhancement (editable
  prompt); History (sections + detail sheet + export + re-transcribe); Logs; Settings;
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
10. **Audio duration** never computed/shown (`durationAudio` unpopulated).
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
17. **Configurable output directories** — output is currently hardcoded to
    `~/Whisper Memory/transcripts/` (and the recordings dir). Let the user choose where
    transcripts / summaries / recordings are written. This is what `defaultOutputDir`
    (#7) was meant for — wire it up (folder picker in Settings, security-scoped bookmark)
    instead of dropping it.
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
20. **Native window controls for the chrome** — `.windowStyle(.hiddenTitleBar)`
    (`WhisperBoxApp.swift:32`) + the custom 52px top bar (`RootView.swift:103–112`) cover the
    title-bar region, so the window can't be dragged, double-clicked to zoom, or comfortably
    resized. **Chosen direction: minimal fix** — keep the custom dark `Theme`, make the top
    bar a draggable title-bar region (e.g. `WindowDragGesture` / transparent native title bar)
    so move + zoom + resize work again. _Deferred alternative:_ full native
    `NavigationSplitView` + `.toolbar` — most native, but forces a **light/dark theming**
    project (`Theme` is dark-only; `.preferredColorScheme(.dark)` hard-forced at
    `RootView.swift:40`), so not chosen now.
21. **Switch primary UI language to English** — UI strings are hardcoded **French** across
    `RootView.swift`, `Views/SectionViews.swift`, `Components.swift`, `WhisperBoxApp.swift`.
    Either (a) straight replacement → single-language English app, or (b) proper localization
    (String Catalog `.xcstrings`, English base + French secondary, `LocalizedStringKey`).
    Decision TBD. Note: UI language is separate from the transcription `defaultLanguage`
    (`AppSettings`) and the Claude prompt language — don't conflate them.

## Remaining next steps
- Polish: History search (#9), audio duration (#10), menu-bar red glyph (#11).
- Feature: configurable output directories (#17) — wire up `defaultOutputDir` (#7).
- UX: global recording shortcuts (#19), native window controls — minimal fix (#20),
  English UI (#21).
- Robustness: transcription sleep-checkpoint (#12), test target (#14).
- Distribution: notarization (#16) when going beyond beta testers.
- Tidy: drop the unused `defaultModel` setting (#7).
