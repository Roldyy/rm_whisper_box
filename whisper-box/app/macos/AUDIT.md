# WhisperBox (native macOS) — Implementation Audit

Snapshot of the Swift app: **cleanly layered, building green.** Purpose: track health
and next steps. _Last updated: 2026-06-26 — quick-wins batch (#1–#6, #8, #13) landed._

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

## Remaining next steps
- Polish: History search (#9), audio duration (#10), menu-bar red glyph (#11).
- Robustness: transcription sleep-checkpoint (#12), test target (#14).
- Distribution: notarization (#16) when going beyond beta testers.
- Tidy: drop the unused `defaultModel`/`defaultOutputDir` settings (#7).
