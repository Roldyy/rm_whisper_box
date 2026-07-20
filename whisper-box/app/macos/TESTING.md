# WhisperBox — testing

## How to run
```bash
cd whisper-box/app/macos
swift test                       # all unit tests (Tests/WhisperBoxTests)
swift test --filter LiveTranscriberTests
```
Unit tests cover **pure logic only** — no UI, no WhisperKit model, no network, no TCC. They run
in well under a second. Everything permission-gated (recording, video, call detection, a live
Odoo push) is **not** unit-testable and must be verified by hand in the signed app bundle
(Xcode Run or `build-dmg.sh`); see the runtime caveat in `AUDIT.md`.

There is no Playwright-style UI driver for a native macOS `MenuBarExtra` app: XCUITest is the only
option and is too flaky + TCC-blocked to be worth it here. Strategy = XCTest for logic + manual
on-device checks for the rest.

## Current coverage (43 tests, `swift test`)
- ✅ `OutputFormatter` — txt/srt/vtt rendering, timestamp formatting, empty/negative edges.
- ✅ `OdooService` — `htmlFromMarkdown` (headings incl. `##`, `-`/`*` bullets, bold, blockquote,
  `---`, escaping) **and the JSON-RPC transport** via a `URLProtocol` stub: authenticate shape +
  uid, auth-failure, server-error message, and the full push flow (auth → partner read → create),
  asserting the create makes a **Private** article (`internal_permission: none` + owner member).
- ✅ `AudioMixer` — two-source mixing at the watermark, `finish()` drain, the `Int.max`
  finished-source guard (crash regression), paused-sample dropping, and the stall detector via an
  injected clock (drop-idle-while-other-moves, no-drop-when-both-idle, no-false-positive-after-resume).
- ✅ `WAVWriter` — `flushHeader()`/`finalize()` write a valid RIFF `dataSize` (the #22 crash-safety fix).
- ✅ `AppPaths` — collision suffixing, strict `isInRecordingsDir`, staging-is-local, and
  `adoptStaging` crash-recovery (adopt non-empty WAV, drop empty fragments, discard non-WAV).
- ✅ `LiveTranscriber` — finish→transcript pipeline, trim/drop-empty, empty-engine, start-resets,
  cancel-clears, the **incremental (non-forced) drain pass + VAD gate + confirm-all-but-last-two
  split**, and the stale-pass-from-a-cancelled-session guard (deterministic via an `actor` stub +
  fresh-pass happens-after barrier).
- ✅ `AudioDecode` (drop-a-file transcribe) — mono 16k WAV, **stereo 44.1k WAV** (resample +
  downmix), **AAC `.m4a`**, an undecodable file, and a **video-only `.mp4`** (no audio track →
  the explicit guard). Fixtures are generated at runtime.

## Coverage (measured 2026-07-20)
```bash
swift test --enable-code-coverage
BIN=.build/arm64-apple-macosx/debug/WhisperBoxPackageTests.xctest/Contents/MacOS/WhisperBoxPackageTests
xcrun llvm-cov report "$BIN" -instr-profile=.build/arm64-apple-macosx/debug/codecov/default.profdata \
  -ignore-filename-regex='(Tests|\.build|checkouts)/'
```
**Whole-module line coverage is ~9% and that number is meaningless** — ~60% of the code is
SwiftUI views + capture + logging that isn't unit-testable (all 0% by design). The logic files:

| File | Line cov | Note |
|------|---------:|------|
| `OutputFormatter` | ~98% | done |
| `OdooService` | ~96% | markdown + JSON-RPC transport |
| `LiveTranscriber` | ~87% | trimming maths still uncovered |
| `AudioDecode` | ~84% | file-decode path |
| `AppPaths` | ~71% | `cloudStorageProviders` still uncovered |
| `RecorderEngine` | ~48% | `AudioMixer` + `WAVWriter` covered; AV/SCStream capturers 0% |

**0% by design** (verify manually, not via unit tests): `RecordingService`, `CallDetector`,
`TranscriptionManager`, `WhisperKitEngine`, `EnhancementService`, `Log`, `PowerAssertion`,
`KeychainService`, and all views (`RootView`, `WhisperBoxApp`, `Components`, `Theme`, …).

## Remaining gaps, by priority
1. **`LiveTranscriber` buffer trimming** — `trimBuffer`/`enforceMaxBuffer`/`trimLeadingSilence`
   and the VAD silence-skip branch. The incremental-pass + confirm split + session safety are now
   covered; the trimming maths and the 30 s cap aren't (needs a multi-pass drive).
2. **`TranscriptionManager.outputURL` collision** — its own suffixing loop (separate from
   `AppPaths`); entangled with `modelContext`, so lower priority.
3. **`AppPaths.cloudStorageProviders`** — enumerates `~/Library/CloudStorage`; low value.

## Not worth unit-testing (verify manually)
`RecordingService` state machine, `CallDetector` (CoreAudio), `EnhancementService` (subprocess),
and all SwiftUI views — too entangled with SCStream / CoreAudio / process spawning / TCC.
