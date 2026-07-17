# Whisper Box — App Review & Improvement Report

_Date: 2026-06-24 · Branch: `feature/screencapturekit-recording`_

This is a review of the current app (FastAPI + mlx-whisper backend, React/Vite
frontend, rumps menu-bar shell, packaged as a macOS `.app`). It focuses on the
slow file picker you mentioned, plus correctness, performance, and UX issues
found while reading the code.

Items are tagged **[P1]** (fix soon — correctness/perf), **[P2]** (worthwhile),
**[P3]** (polish/nice-to-have).

---

## 1. The slow file picker (your example)

**Where:** [api/system.py](app/backend/api/system.py) → `osascript -e 'choose file…'`,
triggered from [FileDropZone.tsx](app/frontend/src/components/FileDropZone.tsx).

**Root cause — it is _not_ process startup.** I measured `osascript` cold start
at ~50 ms, so the subprocess is not the bottleneck. The real problem is **window
ownership and focus**:

- `osascript` runs as a detached child of the Python backend, which is a
  background/agent process (the `.app` is a menu-bar `LSUIElement`-style app, not
  a regular foreground app). The `choose file` panel therefore opens **behind the
  browser window and without keyboard focus**.
- The user clicks "choisir un fichier", the UI shows the `En attente…` spinner,
  but the dialog is hidden behind Chrome/Safari. They have to hunt for it in the
  Dock or via ⌘-Tab. That hunt is the "slowness" you feel — the dialog is already
  open, just not visible/frontmost.
- `choose file` also doesn't remember the last directory, so every pick starts
  from the same default location.

### Options (cheapest → cleanest)

**[P1] Option A — make the panel frontmost & remember last dir (smallest change).**
Have `osascript` activate itself and seed a default location. Persist the last
directory chosen and pass it back in next time:

```python
# api/system.py
_SCRIPT = '''
try
    set theFile to POSIX path of (choose file with prompt "Choisir un fichier audio ou vidéo"%LOCATION%)
    return theFile
on error number -128
    return ""
end try
'''
# Run with `osascript -e 'tell application "System Events"' ...` is what triggers
# the TCC prompt you wanted to avoid — instead activate the osascript process:
#   osascript -e 'tell me to activate' -e '<choose file script>'
```

Adding `tell me to activate` before `choose file` brings the panel to the front
reliably and costs nothing in permissions. Store the chosen file's parent dir
(e.g. in the `settings` table) and inject it as
`default location (POSIX file "…")` so repeated picks open where the user left off.
This alone will remove ~90% of the perceived slowness.

**[P2] Option B — use a real `NSOpenPanel` from the menu-bar app process.**
The rumps app _is_ a proper `NSApplication` running the main NSRunLoop, so a
PyObjC `NSOpenPanel` shown from that process opens instantly, frontmost, and
focused — no subprocess at all. The web button would signal the main thread
(reuse the `status_bridge`/`queue.Queue` pattern already in
[status_bridge.py](app/backend/services/status_bridge.py)) to present the panel
and push the path back. More moving parts, but the "native app" feel.

**[P3] Option C — drop the native dialog entirely: browser file upload.**
The only reason a native dialog exists is that mlx-whisper needs a real
filesystem path and browsers hide absolute paths. If you instead accept a
multipart upload (`<input type="file">` → POST the bytes → save to a temp dir →
transcribe), the picker becomes the instant browser-native one, works without
osascript, and is portable beyond macOS. Cost: you stream/copy the media file
(can be large) and manage temp cleanup. `python-multipart` is already a
dependency. Best long-term direction if you ever leave the single-machine model.

> Recommendation: ship **Option A** now (tiny, high impact), keep **Option C** in
> mind as the real fix if the app grows.

---

## 2. Backend correctness

**[P1] Blocking calls freeze the entire event loop during a job.**
In [whisper_runner.py:396](app/backend/services/whisper_runner.py#L396) and
[:404](app/backend/services/whisper_runner.py#L404), `get_audio_duration()`
(a blocking `ffprobe` subprocess, up to 10 s) and `load_model()` (blocking
model download/load — seconds to **minutes** on first download of a large model)
are called **directly inside the async `run_job`**. Only `_transcribe_in_thread`
is offloaded via `asyncio.to_thread`. While the model loads, the whole backend is
frozen: WebSocket progress, `/api/recording/status`, the menu-bar poll, and any
other request all hang. Wrap both in `await asyncio.to_thread(...)`:

```python
duration_audio = await asyncio.to_thread(get_audio_duration, job.source_path)
repo, device_used = await asyncio.to_thread(load_model, job.model)
```

**[P1] Duplicate `/jobs/{job_id}/cancel` route — one is dead and inconsistent.**
The endpoint is defined twice: [transcription.py:112](app/backend/api/transcription.py#L112)
(sets `status="cancelled"` in the DB + signals the token) and
[jobs.py:56](app/backend/api/jobs.py#L56) (only signals the token, no DB update).
Both routers are mounted; FastAPI keeps the **first** registered, so behavior
depends on include order in [main.py](app/backend/main.py#L65). Delete the
`jobs.py` copy to avoid a future reorder silently dropping the DB status update.

**[P2] Cancel can be overwritten by a finishing job (race).**
`cancel_job` commits `status="cancelled"` from the request session, but `run_job`
runs in its own session with `expire_on_commit=False` and, on completion, writes
`status="success"`. If the job finishes between the cancel and the next
cancellation-token check, the success write wins. Re-read and honor a `cancelled`
status before the final success commit in `run_job`.

**[P2] The progress bar is not real-time — it fills only after transcription ends.**
`mlx_whisper.transcribe()` is **not streaming**: it blocks until the whole file is
done, then `_transcribe_in_thread` replays the segments through `progress_cb`
([whisper_runner.py:344](app/backend/services/whisper_runner.py#L344)). So the UI
sits at 0% for the entire job, then races 0→100% at the very end. Either (a) be
honest and show an indeterminate spinner with elapsed time, or (b) chunk the audio
and transcribe segment-by-segment for genuine progress. Worth setting user
expectations either way.

**[P3] `_add_missing_columns` is a hand-rolled migration.**
[database.py:42](app/backend/database.py#L42) adds missing columns but can't handle
type changes, drops, renames, or non-scalar defaults. Fine for now; if the schema
keeps evolving, adopt Alembic before it bites.

**[P3] `datetime.utcnow()` is deprecated** (Py 3.12+) — used across
whisper_runner/transcription/jobs. Switch to `datetime.now(datetime.UTC)`.

---

## 3. Frontend

**[P1] WebSocket URL is hardcoded; no reconnect.**
[useTranscriptionWs.ts:42](app/frontend/src/hooks/useTranscriptionWs.ts#L42) hardcodes
`ws://127.0.0.1:7843/...` while [client.ts](app/frontend/src/api/client.ts#L99)
correctly uses `window.location.origin`. If the port/host ever changes (or the app
is opened via `localhost`), the socket breaks. Derive it:
`` `${location.protocol === 'https:' ? 'wss' : 'ws'}://${location.host}/api/ws/${jobId}` ``.
Also, `ws.onerror` only invalidates queries — a dropped socket mid-job leaves the
UI stuck with no retry. Add a bounded reconnect/backoff.

**[P2] `done`/`error` clear the job after a fixed `setTimeout` (3 s / 5 s).**
[useTranscriptionWs.ts:66](app/frontend/src/hooks/useTranscriptionWs.ts#L66) — if the
component unmounts in that window the timer still fires against stale state. Track
and clear the timeout in the effect cleanup.

**[P3] `runningJobs` Map in zustand** is copied on every progress tick
([appStore.ts:48](app/frontend/src/stores/appStore.ts#L48)). Fine at current scale;
just noting it grows O(n) per update if many concurrent jobs are ever added.

---

## 4. Security & robustness (local-only app — mostly low risk)

**[P2] No size/duration guard on input.** `_load_audio`
([whisper_runner.py:283](app/backend/services/whisper_runner.py#L283)) reads the
**entire** decoded PCM stream into memory via `subprocess.run(capture_output=True)`.
A multi-hour file is hundreds of MB of float32 and can spike memory. Consider a
duration cap or streaming decode.

**[P3] `validate_output_dir` accepts any existing directory** and
`validate_source_path` any readable file. Acceptable because the server binds to
`127.0.0.1` and is single-user, but worth a comment documenting that assumption.

**[P3] CORS allows `http://localhost:3000` with `allow_credentials=True`** in the
shipped build ([config.py:12](app/backend/config.py#L12)). Harmless locally; strip
the dev origin from production config for cleanliness.

**[P3] `ws_manager._send` catches `(WebSocketDisconnect, RuntimeError, Exception)`**
— the first two are subsumed by `Exception`. Simplify to `except Exception`.

---

## 5. Build / repo hygiene

**[P2] The repo contains two full copies of the backend:**
`app/backend/**` (source) and
`WB - Whisper Box.app/Contents/Resources/**` (bundled copy). Editing source does
**not** update the bundle, so it's easy to test stale code. The committed `.app`
also bloats the repo and diffs. Recommend: `.gitignore` the built `.app` and rely
on the `rebuild` skill to regenerate it; keep only source under version control.

**[P3] `.DS_Store` is tracked** (shows as modified in git status). Add to
`.gitignore` and `git rm --cached`.

---

## Suggested order of attack

1. **[P1]** `to_thread` the two blocking calls in `run_job` — biggest real perf win.
2. **[P1]** File picker Option A (`tell me to activate` + remembered dir).
3. **[P1]** Remove the duplicate cancel route; derive the WS URL from `location`.
4. **[P2]** Honest progress UX; cancel race; `.gitignore` the built `.app` + `.DS_Store`.
5. **[P3]** Everything else as cleanup.
