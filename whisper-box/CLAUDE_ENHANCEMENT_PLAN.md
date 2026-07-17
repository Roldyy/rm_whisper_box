# Plan: Claude Transcript Enhancement (via Claude subscription, no API key)

## Goal

After (or on-demand for) a transcript, run it through Claude to produce a
**summary / cleanup / action items**, authenticated against the user's Claude
subscription — **no `ANTHROPIC_API_KEY`, no per-token API billing**.

---

## Auth approach (core decision)

Use the **logged-in Claude CLI in headless mode** (`claude -p`) as a subprocess,
rather than the Python Agent SDK.

- **Why `claude -p` over the Agent SDK:** this repo already shells out to
  subprocesses (`SCRecorder`, `ffprobe`, `git`) — it's the idiomatic pattern
  here, adds **zero pip dependencies**, and `claude -p` draws from the
  subscription. The Agent SDK would add the `claude-agent-sdk` package *and*
  still require the same Node CLI underneath.
- **Auth mechanics:** a long-lived OAuth token from `claude setup-token`
  (requires active Pro/Max), passed to the subprocess via
  `CLAUDE_CODE_OAUTH_TOKEN`.
- **Critical guardrail:** the runner must build a clean subprocess env that
  **explicitly removes `ANTHROPIC_API_KEY`** — if it leaks in, the CLI silently
  bills per-token instead of using the subscription.

### Token storage — macOS Keychain (decided)

The OAuth token is a credential and will be stored in the **macOS Keychain**, not
in the SQLite DB.

- Write: `security add-generic-password -a "$USER" -s "whisperbox-claude-oauth" -w "<token>" -U`
- Read:  `security find-generic-password -a "$USER" -s "whisperbox-claude-oauth" -w`
- Delete: `security delete-generic-password -s "whisperbox-claude-oauth"`
- Wrapped in a small `services/keychain.py` helper (`set_token`, `get_token`,
  `delete_token`) shelling out to `/usr/bin/security`.
- The `Setting` table stores only a non-secret boolean like
  `claude_token_present` for UI state; the token value itself never touches the DB.

---

## Backend changes

1. **`services/keychain.py`** (new) — thin wrapper over the `security` CLI:
   `set_token(value)`, `get_token() -> str | None`, `delete_token()`.

2. **`services/claude_runner.py`** (new) — core wrapper:
   - `check_claude() -> (available, version, auth_mode)`: runs `claude --version`
     and detects whether a token/login is present and whether an API key would
     conflict. Mirrors the existing `check_ffmpeg()` pattern.
   - `enhance_text(text, mode, model, cancel_token, progress_cb) -> str`: builds
     the prompt per `mode` (summary / cleanup / action-items), spawns
     `claude -p --model <model>` with the transcript on stdin, env scrubbed of
     `ANTHROPIC_API_KEY` and injected `CLAUDE_CODE_OAUTH_TOKEN` (read from
     Keychain), captures stdout. Runs via `asyncio.to_thread` like the whisper
     call. Honors the existing `CancellationToken`.

3. **`services/whisper_runner.py`** — after step 7 (transcript file written), if
   `claude_enabled` + `claude_auto_after_transcribe` settings are on, run
   `enhance_text` and write a sibling file `{stem}_{ts}.summary.md`. Stream a
   `ws_manager.send_log` line ("Enhancement Claude en cours…") and reuse the
   existing done/error flow. Failures here must be **non-fatal** — the transcript
   already succeeded.

4. **`api/claude.py`** (new router, registered in `main.py`):
   - `GET  /api/claude/status` → CLI installed? token present (Keychain)? API-key
     conflict? (drives Settings UI readiness).
   - `POST /api/claude/token` → save a pasted token to Keychain.
   - `DELETE /api/claude/token` → remove it from Keychain.
   - `POST /api/claude/verify` → tiny test prompt to confirm the token works.
   - `POST /api/transcripts/{job_id}/enhance` → run Claude on an already-completed
     transcript (powers a manual "Enhance" button), enqueued through the existing
     `job_queue` so it streams over WS.

5. **Settings** — stored in the existing `Setting` key/value table (no schema
   migration needed):
   - `claude_enabled`, `claude_token_present` (bool only — token lives in
     Keychain), `claude_model` (default `claude-opus-4-8`, with a cheaper option
     like `claude-sonnet-4-6`), `claude_default_mode`, `claude_auto_after_transcribe`.

---

## Frontend changes

- **SettingsPage:** new "Claude (IA)" section — enable toggle, paste-token field
  (since `claude setup-token` is interactive and can't run server-side, the UX is
  "run this command in Terminal, paste the result" → saved to Keychain via
  `POST /api/claude/token`), model picker, default enhancement mode, "auto-run
  after transcription" toggle, and a **Verify connection** button surfacing the
  `/api/claude/status` result (CLI found ✓, token valid ✓, no API-key conflict ✓).
- **History / Record pages:** an "Enhance with Claude" button per transcript +
  display/download of the summary output. Reuses the existing TanStack Query + WS
  progress patterns.

---

## Dependencies & packaging (flag up front)

- **Runtime requirement:** Node.js + the `@anthropic-ai/claude-code` CLI must be
  installed and logged in on the machine. The `.app` bundles only the Python
  backend — so `/api/claude/status` needs to fail gracefully with clear "install
  the Claude CLI" guidance when it's absent. This is the biggest non-code
  consideration for shipping to others.
- No new Python packages required for the `claude -p` approach.

---

## Known caveats

- **Billing trajectory:** today this draws on the subscription; when Anthropic
  un-pauses the June 15 2026 split, the same usage shifts to the Agent SDK
  dollar-credit pool, then full API rates beyond it. No code change needed, but
  documented.
- **No migration framework:** `init_db()` only does create-tables. Keeping
  everything in the `Setting` table (not new `TranscriptionJob` columns) sidesteps
  needing an `ALTER TABLE`.

---

## Suggested build order

1. `services/keychain.py` + `services/claude_runner.py` + `/api/claude/status` +
   `/api/claude/verify` (prove subscription auth end-to-end from the backend).
2. Settings UI to store/verify the token (Keychain round-trip).
3. Manual "Enhance" endpoint + button.
4. Auto-after-transcription hook + Record-page toggle.

---

## Open product choices (defaults chosen, easy to flip)

- **`claude -p` subprocess** over the Agent SDK.
- **Opt-in manual enhancement first**, auto-after-transcription as a toggle.
