# WhisperBox (native macOS) — Implementation Audit

Snapshot of the Swift app: **~2,360 LOC across 17 files, cleanly layered, building green.**
Purpose: identify next steps.

## Résumé — what's built
- **Architecture:** app-scoped `@Observable` services (`TranscriptionManager`, `RecordingService`)
  so state survives navigation; a **shared engine singleton** (one model in memory);
  clean Services / Views / Models / Theme split.
- **Features:** file transcription with live progress; in-process recording (system + mic,
  system audio optional, pause/resume); live transcript; Claude enhancement (editable
  prompt); History (sections + detail sheet + export + re-transcribe); Logs; Settings;
  sleep resilience (power assertion + graceful finalize); custom dark UI matching the
  mockups; app icon; signed `.dmg` path (`build-dmg.sh`).
- **Portable in concept:** engine, chunker, formatters, job model — clean for any future
  cross-platform move (whisper.cpp core).

## Findings (prioritized)

### 🔴 Correctness / UX
1. **First-run model download shows no real feedback** — `WhisperKit(config)` downloads the
   model on first use; UI sits at "Transcription… 0%". Should show "Préparation du modèle…"
   + download progress (WhisperKit exposes init progress).
2. **⌘R is unwired** — the Record screen hints "appuyez sur ⌘R" but no `keyboardShortcut`
   exists. Wire it or drop the hint.
3. **Cancel doesn't stop WhisperKit mid-job** — `manager.cancel()` cancels the Task, but
   `pipe.transcribe` runs to completion (callback always returns `true`). Honor cancellation
   via the transcribe callback.
4. **Language is always auto-detect (`nil`)** — per-30s-chunk auto-detect can flip language
   on the live path. `AppSettings.defaultLanguage` exists but isn't wired; add a picker.

### 🟡 Tech debt / dead code
5. **`ChunkedTranscriber` + `ChunkPlanner` unused** — live uses `LiveTranscriber`, batch uses
   WhisperKit's internal chunking. Remove or repurpose for transcription pause/checkpoint.
6. **`ExecutionLog` model never written** — `LogsView` shows jobs, not logs. Remove or use.
7. **Unused `AppSettings` fields** — `defaultModel`, `defaultOutputDir` not wired (model
   hardcoded in two places; output written next to source).
8. **Output files land next to the source** rather than a dedicated transcripts folder —
   can clutter user folders / hit read-only locations.

### 🟢 Deferred features / polish
9.  History **search field** (in mockup, not built).
10. **Audio duration** never computed/shown (`durationAudio` unpopulated).
11. **Menu-bar red glyph** while recording (currently shows elapsed time).
12. **Transcription sleep-checkpoint** (plan §10.3 Path A) — forced sleep mid-transcription
    still interrupts it.
13. **`claude` CLI presence** not checked — enhancement just errors if missing.

### 🔵 Infra
14. **No tests** — pure-logic services (`OutputFormatter`, `ChunkPlanner`) are trivially
    unit-testable; add an XCTest target.
15. **Swift 5 language mode** — Swift 6 strict concurrency would surface a few `@Sendable`
    issues (currently fine).
16. **Notarization** (Tier 2) for distribution beyond a few beta testers.

## Recommended next steps
1. **Quick wins:** model-download feedback (#1), ⌘R (#2), real cancellation (#3),
   delete dead code (#5, #6).
2. **Then:** language setting (#4), output-to-transcripts-dir (#8), `claude` CLI check (#13).
3. **Then features:** History search (#9), audio duration (#10).
4. **Before shipping wide:** small test target (#14) + notarization (#16).
