# WhisperBox (native macOS) — Implementation Audit

Current health + backlog for the Swift app (`whisper-box/app/macos`). Building green
(`swift build`). **This is a state doc, not a changelog — the fix history lives in `git log`.**
_Last updated: 2026-07-20._

> **Runtime caveat:** `swift build` compiles but produces no bundle. Recording, call detection,
> video, and Odoo paths are TCC/permission-gated and only run from the **signed app bundle**
> (Xcode Run or `build-dmg.sh`). The 2026-07 recording/detection/video/Odoo work has **not been
> runtime-tested** yet — only compiled and code-reviewed. Unit tests cover the pure logic (`swift test`).

## What's built
- **Architecture:** app-scoped `@Observable` services (`TranscriptionManager`, `RecordingService`,
  `CallDetector`) injected via `.environment` so state survives navigation; a shared engine
  singleton (one model in memory); Services / Views / Models / Theme split.
- **Transcribe:** drop/pick a file → live streaming progress; configurable language + output
  format (txt/srt/vtt); on-demand high-quality re-transcribe.
- **Record:** system audio (ScreenCaptureKit) + mic (AVFoundation), each toggle persisted;
  pause/resume; live rolling-window transcript (VAD + confirmed/unconfirmed); durable WAV
  (local staging → move into output; crash-safe header; quit-safe finalize; stall guard).
- **Video (optional):** full-screen or single-app `.mp4` (H.264) alongside audio, as a separate
  deliverable with "Play video" in History.
- **Auto-start:** CoreAudio mic-in-use detector → Off / Ask / Auto when Teams/Zoom/Webex/Slack/
  Discord starts using the mic.
- **Enhance:** Claude CLI summary (editable French meeting-synthesis prompt; timeout + stderr capture).
- **Odoo Knowledge push:** JSON-RPC, Private article, API key in Keychain; manual + auto-after-summary.
- **Cloud output:** the output folder can be a OneDrive/iCloud sync root (one-tap picker).
- **History / Logs / Settings**, sleep resilience, custom dark UI + icon, Developer ID-signed +
  notarizable `.dmg` (`build-dmg.sh`).

## Open backlog
- **#34 — two-mode recording (mic-only · mic + app):** the mode-selector UI + a **Core Audio
  process-tap** backend (to drop the Screen Recording permission for audio-only capture) is not
  built. Mic-only already works and app-scoped *video* exists (#35); the win here is
  permission-light *audio* capture of one app. Largest remaining item; overlaps #36's CoreAudio work.
- **#19 — system-wide recording hotkeys:** unfocused start/stop + pause/resume via Carbon
  `RegisterEventHotKey` (no entitlement) or a small dep, configurable in Settings. Not started.
- **#12 — mid-transcription sleep checkpoint:** resumable batch transcription (recording sleep is
  already handled). Large/risky. The dead `TranscriptionJob` fields (`lastCompletedChunk`,
  `partialTranscript`, the unused advanced `DecodingOptions`) exist only for this — drop them if #12 is.
- **#15 — Swift 6 language mode:** would surface a few `@Sendable`/isolation issues (fine under
  Swift 5 today, but this app has real concurrency — keep it correct regardless).

## Known residuals / trade-offs
- **Video:** paused time is a frozen span in the `.mp4` (we prioritized *not recording paused
  content* over A/V-timeline parity — the two files aren't muxed); fixed ~30 fps; requires the
  Screen Recording permission when enabled. App-scoped video + "system audio" records full screen
  so the audio stays complete (one SCStream filter can't do both).
- **Odoo:** needs user-side setup (Enterprise/Online Knowledge, Custom-plan External API, an API
  key); no configurable parent article yet; the "View in Odoo" link uses the universal
  `/web#id=…&model=knowledge.article` form.
- **Tidy:** `AppSettings.defaultModel` is unused (model locked in the UI) — drop the field.
  `TranscriptionJob.detectedLanguage` is never written (cheap to populate from WhisperKit).
- **Menu-bar glyph** relies on MenuBarExtra rendering the label in colour; if a build shows it
  monochrome, swap to a non-template `NSImage`.

## Resolved (reference only — detail in git + code)
- **UX / correctness:** #1 model-download feedback · #2 ⌘R · #3 cancellation · #4 language ·
  #9 History search · #10 audio duration · #11 menu-bar glyph · #13 claude-CLI presence ·
  #20 native window controls · #21 English UI.
- **Tech debt:** #5 removed unused ChunkedTranscriber · #6 removed dead model · #7/#8 output
  location · #17 configurable output dirs · #18 real logging · #29 durationRun · #30 removed old
  SCRecorder + binary · #31 claude CLI paths · #32 capture toggles persisted across all start paths.
- **Durability / correctness (07-02 sweep):** #22 quit/crash-safe WAV · #23 start-failure cleanup ·
  #24 mixer stall guard · #25 output-name collisions · #26 enhancement hardening · #27 recorded-job
  duration · #28 live-slice FIFO · #33 delete-with-files.
- **Requested features (07-19):** #35 video · #36 auto-start · #37 cloud/staging output · #38 Odoo push.
- **#16 notarization:** `build-dmg.sh` signs with Developer ID + Hardened Runtime and
  notarizes+staples when a `notarytool` keychain profile is present, else emits a
  signed-not-notarized `.dmg` with Gatekeeper instructions. See `PACKAGING.md`.
- **#14 tests:** unit target `Tests/WhisperBoxTests` (run `swift test`) covering the pure logic —
  `OutputFormatter`, `OdooService.htmlFromMarkdown`, `AppPaths`, `AudioMixer`. **Coverage status +
  prioritized gaps live in `TESTING.md`** (top gap: `LiveTranscriber`).

Two `/code-review` rounds (Opus) plus two `fable` review rounds hardened the 07-19 work (VAD
rolling-min floor, LiveTranscriber session/drain safety, start/stop reentrancy via `isStarting` +
synchronous `.stopped`, the `AudioMixer.append` Int.max guard, SIGPIPE handling, staging-adoption
safety, delete-with-files shared-source guard, …). See `git log` for the specifics.
