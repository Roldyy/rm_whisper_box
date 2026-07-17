# WhisperBox → Native Swift + whisper.cpp — Migration Plan

> Status: **planning / pre-implementation**. This document scopes a migration from
> the current Python-backend + React-frontend + Swift-recorder architecture to a
> single native macOS app (SwiftUI + whisper.cpp). It is a parallel rebuild to
> feature parity, **not** an in-place refactor.

---

## 1. Why migrate

Every recurring pain in this app traces back to the Python + web + subprocess split:

| Current pain | Root cause | Fixed by native Swift? |
|---|---|---|
| No live transcription progress; UI "stuck on Modèle prêt" | mlx-whisper is batch-only (one opaque blocking call) | ✅ whisper.cpp streams via `new_segment_callback` / `progress_callback` |
| 12× intermittent slowdown on long recordings | `condition_on_previous_text` loops + no temperature fallback | ⚠️ mitigated by config + streaming windows (engine-agnostic) |
| Hard to package / distribute | Bundling a Python runtime + mlx + ffmpeg + node build | ✅ single signed `.app` bundle |
| Brittle plumbing (WebSocket, `status_bridge`, subprocess recorder, localhost server) | Cross-process, cross-language IPC | ✅ in-process function calls + Combine/Observation |
| `osascript` file-picker hacks (see APP_REVIEW.md) | Browser can't see filesystem paths | ✅ native `.fileImporter` / `NSOpenPanel` |
| No ANE usage ("Apple Neural Engine" log is wrong — mlx is GPU-only) | mlx has no Core ML path | ✅ whisper.cpp Core ML encoder runs on ANE (power-efficient on long jobs) |

The recorder is **already** Swift (`app/swift/SCRecorder.swift`), so a meaningful chunk of
the hardest native code (ScreenCaptureKit audio capture) already exists and can be lifted
in-process.

---

## 2. Current architecture inventory (what must be replaced or ported)

### Backend (Python / FastAPI) — `app/backend/`
- **API layer** (`api/`): `jobs`, `transcription`, `recording`, `ws`, `claude`, `settings`, `logs`, `system` — REST + WebSocket endpoints.
- **Services** (`services/`):
  - `whisper_runner.py` — orchestrates transcription (mlx-whisper), output formats, progress callbacks, ffmpeg decode (`_load_audio`), ffprobe duration.
  - `recording_service.py` — spawns/stops the `SCRecorder` Swift binary as a subprocess.
  - `claude_runner.py` — **shells out to the `claude` CLI** (`claude -p --model X`), modes: `summary`/`cleanup`/`action-items`, French prompts. Uses OAuth token (subscription billing), strips `ANTHROPIC_API_KEY`.
  - `keychain.py` — wraps `/usr/bin/security` to store the Claude OAuth token.
  - `job_queue.py`, `ws_manager.py`, `status_bridge.py` — async job queue, WebSocket broadcast, menu-bar status bridge.
- **Models** (`models/`): `job` (`transcription_jobs`), `log` (`execution_logs`), `setting` (`settings`) — SQLAlchemy over SQLite (`~/Whisper Memory/app.db`, WAL).
- **`launcher.py`** — `rumps` menu-bar app (recording indicator, polls every 2s).
- **`config.py`** — paths: `~/Whisper Memory/` (`recordings/`, `uploads/`, `transcripts/`, `app.db`); `SUPPORTED_MODELS`, `SUPPORTED_LANGUAGES`, `SUPPORTED_OUTPUT_FORMATS`.

### Frontend (React / Vite / TS) — `app/frontend/src/`
- Pages: `RecordPage`, `TranscribePage`, `HistoryPage`, `LogsPage`, `SettingsPage`.
- Components: `TranscribeForm`, `HistoryTable`, `LogViewer`, `ProgressBar`, `FileDropZone`, `RecordButton`, `StatusBadge`, `ConfirmDialog`.
- `hooks/useTranscriptionWs.ts` — WebSocket client for live progress.
- `stores/appStore.ts` — client job state.

### Swift (already native) — `app/swift/`
- `SCRecorder.swift` — ScreenCaptureKit audio capture → 16 kHz mono WAV (`WAVWriter`, downmix/resample). **Reusable.**

---

## 3. Target architecture

```
┌─────────────────────────────────────────────────────────┐
│  WhisperBox.app  (single SwiftUI process, no server)      │
│                                                            │
│  SwiftUI views (Record / Transcribe / History / Logs /     │
│                 Settings)  +  MenuBarExtra                 │
│        │  @Observable view models (Observation/Combine)    │
│        ▼                                                   │
│  TranscriptionService ── whisper.cpp (Metal + Core ML/ANE) │
│        │  in-process progress callbacks                    │
│  RecordingService    ── ScreenCaptureKit (from SCRecorder) │
│  EnhancementService  ── `claude` CLI (Process) or API      │
│  Store               ── SwiftData (or GRDB over SQLite)    │
│  Keychain            ── Security.framework                 │
│  Audio decode        ── AVFoundation (no ffmpeg)           │
└─────────────────────────────────────────────────────────┘
```

No FastAPI, no WebSocket, no localhost, no Python, no node build, no ffmpeg binary,
no subprocess recorder. Live progress becomes ordinary in-process callbacks feeding
`@Observable` view models.

### 3.1 Audio pipeline — direct buffer feed, no format round-trip

A key win of going native: capture audio in real time via **AVFoundation / ScreenCaptureKit /
CoreAudio** and hand the PCM buffers **straight to whisper.cpp** — no disk file, no ffmpeg,
no Python↔system format juggling.

**This eliminates a redundant round-trip that exists today.** Current flow:

```
SCRecorder: capture → downmix/resample to 16kHz mono Float
          → encode to WAV bytes → write to disk
Python:     read WAV from disk → ffmpeg decode back to s16le
          → numpy float32 → mlx
```

The audio is converted to 16 kHz mono Float **inside `SCRecorder.swift` already**
(`AVAudioConverter` → `floatChannelData`), then needlessly serialized to a WAV file and
decoded back — purely because the engine lives in another process and language.

whisper.cpp's `whisper_full()` takes exactly `const float* samples` at **16 kHz mono** — i.e.
*precisely the format the capture converter already produces*. So in the native app:

```
ScreenCaptureKit/AVAudioEngine: capture → 16kHz mono Float buffer
                              → whisper.cpp (in-process, zero copies to disk)
```

Implications:
- **File transcription:** decode once with `AVAudioFile`/`AVAudioConverter` → Float buffer → whisper.cpp. No ffmpeg dependency to bundle/codesign.
- **Live transcription (Phase 5):** the *same* capture buffers that build the saved WAV are simultaneously streamed into a whisper.cpp sliding window — one capture, two consumers (disk archive + live transcript), no extra conversion.
- Removes a class of bugs (the `duration_audio` ffprobe failure, WAV-header quirks, ffmpeg path/codesigning) entirely.

A WAV file may still be written **as the saved artifact** for archive/re-transcription — but it
is no longer on the critical path *into* the engine.

---

## 4. Component mapping (old → new)

| Current | Target |
|---|---|
| FastAPI REST endpoints | Direct method calls on service objects |
| `ws.py` + `ws_manager.py` + `useTranscriptionWs.ts` | In-process callbacks → `@Observable` / `AsyncStream` |
| `status_bridge.py` (menu-bar bridge) | Shared `@Observable` app state |
| `whisper_runner.py` (mlx) | `TranscriptionService` over whisper.cpp |
| `_load_audio` (ffmpeg) + `get_audio_duration` (ffprobe) | `AVAudioFile` + `AVAudioConverter` (native, fixes the `duration_audio` bug for free) |
| Capture → WAV file → disk → ffmpeg decode → float32 → mlx (round-trip) | Capture buffers fed **directly** to whisper.cpp (no disk, no ffmpeg) — see §3.1 |
| Output-format writers (txt/srt/vtt) | Small Swift formatter (port timestamp logic) |
| `recording_service.py` + `SCRecorder` subprocess | `RecordingService` using `SCRecorder.swift` **in-process** |
| `claude_runner.py` (`claude` CLI) | `EnhancementService` via `Process` (same CLI) — see §6 |
| `keychain.py` (`security` CLI) | `Security.framework` Keychain Services |
| SQLAlchemy models + SQLite | SwiftData models (or GRDB over existing `app.db`) |
| `launcher.py` (rumps) | SwiftUI `MenuBarExtra` |
| React pages/components | SwiftUI views (1:1 mapping above) |
| Vite dev server / build | Xcode build |

---

## 5. Key technical decisions (resolve in Phase 0 spikes)

### 5.1 Engine: whisper.cpp vs WhisperKit
- **whisper.cpp** (the requested target): C/C++, SwiftPM-integrable (xcframework or SPM target), Metal + Core ML encoder (ANE), `new_segment_callback`/`progress_callback`, `stream` example for live. Requires generating/bundling GGML/GGUF weights **and** the Core ML encoder (`models/generate-coreml-model.sh`).
- **WhisperKit** (Argmax) — strong alternative worth a spike: pure-Swift, Core ML, built-in streaming + model hub, trivial SPM integration. Less C-bridging, but less low-level control.
- **Decision rule:** spike both, benchmark accuracy + speed against current mlx (target: match the healthy ~0.11× realtime we measured), pick on integration cost vs control.

#### 5.1.1 Phase 0 benchmark results (measured) — same 2h19m (8356s) French file

| Engine | Transcription | Realtime factor | Model load | Time-to-first-segment | Streaming | HW path |
|---|---|---|---|---|---|---|
| **mlx large-v3-turbo** (current) | 951s | 0.114× | ~2.1s | — (none) | ❌ batch-only | GPU (Metal) |
| **whisper.cpp** (GGML) | **903s** | **0.108×** | **1.2s** | **3.7s** | ✅ `new_segment_callback` (demoed) | GPU (Metal) |
| **WhisperKit** (Core ML) | 928s | 0.111× | cold 561s* | not measured | ✅ callback + `AudioStreamTranscriber` | ANE/GPU |

\* WhisperKit "cold" = first-run model **download (slow network) + Core ML compile**; a warm load is seconds — re-measure warm. The 928s transcription is steady-state and valid.

**Conclusions:**
- **Speed is a wash** — all three within ~5%. Throughput is *not* a deciding factor (settles the earlier "is mlx slower?" thread definitively).
- **Both alternatives stream; mlx cannot** — whisper.cpp showed a **3.7s** time-to-first-segment (excellent live-progress latency); WhisperKit additionally ships a real-time mic pipeline (`AudioStreamTranscriber`).
- **whisper.cpp wins on:** tiny model load (1.2s, no compile), low-level control, reuses GGML weights.
- **WhisperKit wins on:** ANE out-of-the-box (power-efficient on long recordings), built-in real-time streaming, pure-Swift SPM (lowest integration cost). whisper.cpp ran on **Metal GPU, not ANE** — reaching the ANE needs a separate Core ML encoder build.
- **Lean:** for this app's goals (live-during-recording = Phase 5, power efficiency on multi-hour meetings, lowest integration effort), **WhisperKit edges ahead**; whisper.cpp is the pick if low-level control / no-compile model loading matter more. Final call after a warm WhisperKit init measurement.

### 5.2 Persistence: SwiftData vs GRDB-over-existing-SQLite
- **SwiftData** — native, `@Query` integrates with SwiftUI; clean for a rewrite. Needs a one-time importer if old history matters.
- **GRDB** — keeps the existing `app.db` schema and data verbatim; zero data migration.
- **Decision rule:** if preserving existing job history is important → GRDB or a SwiftData importer; otherwise SwiftData greenfield. -> Swiftdata we don't care about history.

### 5.3 Model management
- whisper.cpp weights (e.g. `ggml-large-v3-turbo.bin`) + Core ML encoder are **different files** from mlx's HF repos.
- Decide: bundle a default model in the `.app` (large bundle) vs download-on-first-use into `Application Support` (smaller bundle, needs network + progress UI). Recommend download-on-first-use with a bundled `base` fallback. -> First run, while explaining it to the user.

### 5.4 Distribution & sandboxing — **decide early, it constrains everything**
- The `claude` CLI subprocess and ScreenCaptureKit are **incompatible with Mac App Store sandboxing** as currently designed.
- **Path A (recommended): direct distribution** — notarized `.dmg`, hardened runtime, entitlements for audio/screen capture. Keeps the CLI-based Claude (subscription billing). -> dmg is fine.
- **Path B: Mac App Store** — must drop the CLI and call the Anthropic API directly (per-token billing) and satisfy the sandbox. Different cost model for users.

---

## 6. Claude integration — preserve the subscription model

`claude_runner.py` deliberately runs `claude -p --model <model>` with a Keychain OAuth
token and **strips `ANTHROPIC_API_KEY`** so usage bills against a Claude subscription, not
per-token API. Two options in Swift:

- **Keep the CLI** (`Process` + same env handling) → preserves subscription billing, but requires the `claude` binary to be installed and **rules out the sandboxed Mac App Store**.
- **Switch to the Anthropic API** (`URLSession`, SSE streaming) → self-contained, sandbox-friendly, but per-token billing and a new auth/secret model.

Keychain moves from the `security` CLI to native **Security.framework** either way.
Prompts (`summary` / `cleanup` / `action-items`, French) port verbatim.

---

## 7. Phased migration

> Each phase is independently demoable. Build the new app in a sibling Xcode project
> (e.g. `app/macos/`) while the Python app keeps running, then cut over after Phase 6.

- **Phase 0 — De-risk (spikes, ~no UI): three-way engine benchmark.** Same 2h19m file, same `fr` language, measured against the **mlx baseline (951s, 0.11× realtime)**:
  - **whisper.cpp** — Swift↔C interop spike, streaming `new_segment_callback`. Reuses the GGML model already on disk (from Vibe). Validates speed + live-progress latency (time-to-first-segment).
  - **WhisperKit** — pure-Swift / Core ML spike. Needs its own Core ML model download (~1.5 GB, separate from GGML). Validates the lowest-integration-cost path + ANE usage.
  - Compare on: realtime factor, time-to-first-segment (live UX), integration cost, ANE/power behavior on the long file. Pick the engine here.
  - Decide §5.2 (persistence), §5.4 (distribution).
- **Phase 1 — App skeleton:** Xcode project, SwiftUI shell + navigation, SwiftData (or GRDB) models for jobs/logs/settings, Keychain (Security.framework), Settings screen.
- **Phase 2 — File transcription (parity with "drop a file"):** `TranscriptionService` over whisper.cpp, AVFoundation decode to 16 kHz mono, streaming progress → UI, txt/srt/vtt output. **This proves the core thesis (live progress).**
- **Phase 3 — Recording + menu bar:** lift `SCRecorder.swift` in-process as `RecordingService`; `MenuBarExtra` with recording indicator; auto-enqueue transcription on stop.
- **Phase 4 — Claude enhancement:** `EnhancementService` (CLI or API per §6), modes preserved, write `.summary.md` to `transcripts/`.
- **Phase 5 — Live streaming transcription (the motivating feature):** feed ScreenCaptureKit/AVFoundation PCM buffers **directly** into whisper.cpp sliding windows for real-time transcript during recording (see §3.1). The capture converter already emits 16 kHz mono Float — whisper.cpp's exact input — so the same buffer stream feeds both the saved WAV and the live transcript with zero extra conversion.
- **Phase 6 — History / logs / polish + data import:** History & Logs views; optional one-time import from old `app.db`.
- **Phase 7 — Pause/resume + sleep resilience (see §10):** recording pause/resume (writer gating), chunk-boundary transcription pause/resume, sleep prevention (`IOPMAssertion`) + graceful stop/checkpoint on forced sleep. Depends on the chunked transcription from Phase 5 and the recording state machine from Phase 3.
- **Phase 8 — Packaging:** codesign, notarize, entitlements (audio capture / screen recording), `.dmg`.

---

## 8. Risks & open questions

- **Engine parity:** whisper.cpp accuracy/speed must match mlx's healthy case — verify in Phase 0, not after committing.
- **Core ML conversion friction:** generating the ANE encoder can be finicky per model/macOS version.
- **Permissions:** ScreenCaptureKit audio needs macOS 13+ (SCRecorder comment notes 14.2+ for audio-only); TCC prompts for screen recording + microphone.
- **Effort:** this is a multi-week rewrite, not a port — scope accordingly.
- **Sleep cannot be fully prevented:** `IOPMAssertion` stops *idle* sleep only — forced sleep and lid-close (clamshell, on battery) cannot be blocked by any public API. So the graceful stop/checkpoint path (§10.3) is mandatory, not optional. The `willSleep` window is only a few seconds → finalize work must be fast (WAV header flush + DB write, both cheap).
- **Open:** whisper.cpp vs WhisperKit? CLI-Claude vs API? Minimum macOS version? (Decided inline: SwiftData, direct `.dmg`, first-run model download, no history import.)

---

## 9. Immediate prep steps (before any rewrite)

1. **Phase 0 spike** — stand up a throwaway Swift command-line tool that transcribes one file via whisper.cpp with streaming callbacks; benchmark vs mlx on the known 2h19m recording.
2. **Decisions** — resolve §5.4 (distribution) and §5.2 (persistence) first; they gate everything downstream.
3. **Inventory the data contract** — freeze the current `transcription_jobs` / `settings` schema as the import target.
4. **Keep current app shippable** — land the cheap wins meanwhile (`condition_on_previous_text` default, temperature fallback, `duration_audio` fix, WS "Transcription en cours" heartbeat) so users aren't blocked during the rebuild.

---

## 10. New features: pause/resume & sleep resilience

These are native-app features the current architecture can't do well. Both lean on
the same two foundations as the rest of the plan: the **recording state machine**
(Phase 3) and **chunked transcription** (Phase 5).

### 10.1 Pause / resume — recording
State machine: `idle → recording → paused ⇄ recording → stopped`.
- The `SCStream` (and any `AVAudioEngine` mic tap) **stays alive**; on pause the
  `RecordingService` **gates the writer** — incoming sample buffers are simply not
  appended to the WAV (nor fed to the live transcriber). Paused time is therefore
  excluded and the saved audio stays contiguous — standard pause semantics.
- Avoid `stopCapture()`/`startCapture()` on pause: heavier, risks a re-prompt, and
  breaks continuity. Gating is instant and lossless.
- UI: pause/resume in the Record view **and** `MenuBarExtra`; the elapsed timer
  freezes while paused.

### 10.2 Pause / resume — transcription
Uses the chunked pipeline that already powers live progress:
- A job transcribes audio as a sequence of windows/chunks. **Pause** = stop
  dispatching the next chunk once the current one finishes; persist the completed
  chunk index + partial transcript. **Resume** = continue from the next chunk.
- whisper.cpp can't be interrupted mid-`whisper_full`, but at chunk granularity this
  is clean — pause costs at most the current in-flight chunk (a few seconds), or use
  whisper.cpp's `abort_callback` to hard-stop it immediately.
- Live transcription during recording pauses automatically when the recording pauses
  (no new buffers arrive).

### 10.3 Sleep resilience
This directly fixes the data loss we confirmed earlier (job 33: **4h57m wall-clock but
only 2h19m of audio captured** — the rest lost to sleep). Two complementary layers:

**Layer 1 — Prevent sleep while active (proactive).**
Hold an `IOPMAssertion` (`kIOPMAssertionTypePreventUserIdleSystemSleep`) for the
duration of an active recording or transcription; release on stop/complete. Prevents
*idle* sleep so long jobs finish. **Limit:** cannot stop forced or lid-close (clamshell)
sleep — so Layer 2 is mandatory.

**Layer 2 — Graceful handling on forced sleep (safety net).**
Register for `NSWorkspace.willSleepNotification` / `didWakeNotification`. The willSleep
window is only a few seconds, but enough for a fast finalize:

- **Recording → stop & keep transcript (per request):**
  1. On `willSleep`: stop capture and **finalize the WAV** (write correct RIFF
     header/sizes so the file is valid, not a truncated/corrupt fragment).
  2. Mark the recording `ended_by_sleep` in the store.
  3. Auto-enqueue transcription of the captured audio (and if live transcription was
     on, its partial transcript is already saved). → You wake to a **complete, valid
     recording + transcript**, not a corrupt short file.

- **Transcription → proposed paths (pick in Phase 0/1):**
  - **Path A — Checkpoint & resume (recommended).** Persist completed chunks + last
    audio offset continuously. On `willSleep` stop after the current chunk; on
    `didWake` resume from the next. No lost work; survives even forced/lid sleep.
    Reuses the §10.2 machinery.
  - **Path B — Prevent-sleep for the job.** Hold the Layer-1 assertion so the
    (usually minutes-long) job just completes. Simple, but defeated by forced/lid
    sleep → must fall back to Path A.
  - **Path C — Pause-on-sleep.** Treat `willSleep` as an automatic §10.2 pause, resume
    on wake. Same code path as user-initiated pause.
  - **Recommendation: Path A + Path B together** — prevent idle sleep so most jobs
    finish untouched, and checkpoint so the rare forced/lid sleep is fully recoverable.

### 10.4 Data-model additions
- **Recording:** status enum gains `paused`, `stopped`, `ended_by_sleep`.
- **Transcription job:** `paused` status + a **checkpoint** (last completed chunk
  index / audio offset + accumulated partial transcript) to support resume after pause
  or wake.

---

## 11. Future improvements (post-migration, out of core scope)

### 11.1 Odoo integration — push transcripts into Knowledge
Once the native app is shipping, a natural extension is sending finished transcripts /
Claude summaries to an **Odoo** backend — primarily into the **Knowledge** module as
articles, so meeting notes land in a searchable shared workspace.

- **`OdooService`** (mirrors the `EnhancementService`/`TranscriptionService` pattern):
  `URLSession` + `Codable` over Odoo **JSON-RPC** (`/web/dataset/call_kw`), credentials
  in the Keychain (Security.framework, alongside the Claude token). Prefer JSON-RPC over
  XML-RPC — JSON maps directly to `Codable`.
- **Primary flow — push to Knowledge:** on transcription/enhancement complete (or via an
  explicit "Send to Odoo" action), `create`/`write` a `knowledge.article` with the
  summary (and optionally the full transcript) as the HTML body. Optionally file it under
  a configured parent article/workspace.
- **Secondary ideas:** map Claude `action-items` to `project.task` records; attach the
  source audio/transcript file to the article.
- **Config:** Odoo base URL + API key (Odoo 14+) or session login in Settings; HTTPS
  assumed (add an ATS exception only if the Odoo server is plain HTTP). Direct `.dmg`
  distribution means no network entitlement is required.
- **Status:** future — not part of the core feature-parity migration; listed so the
  service-oriented architecture leaves room for it.

