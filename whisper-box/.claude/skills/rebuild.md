# rebuild

Build the WhisperBox macOS .app bundle.

Runs `app/dev/create-app.command` from the repo root. This script:
1. Builds the React frontend (`npm run build`)
2. Compiles the Swift SCRecorder binary
3. Installs Python dependencies
4. Assembles the `.app` bundle
5. Creates a Desktop alias

## Usage

When the user says "rebuild", "build the app", or similar — follow these steps in order:

### Step 1 — Claude CLI check

Check if the Claude CLI is installed:

```bash
claude --version 2>/dev/null
```

If the command fails (not found), ask the user:
> "The Claude CLI isn't installed. Do you want to install it now? (Required for the AI enhancement feature)"

If they say yes, run:
```bash
npm install -g @anthropic-ai/claude-code
```

Then confirm it worked with `claude --version`.

If the CLI is already installed, silently continue.

### Step 2 — OAuth token check

Check if a token is already stored in the Keychain:

```bash
/usr/bin/security find-generic-password -a "$USER" -s "whisperbox-claude-oauth" -w 2>/dev/null
```

If no token is found (command returns nothing or exits non-zero), ask the user:
> "No Claude OAuth token found. Do you want to set one up now? (You can skip this and do it later in the app's Settings page)"

If they say yes:
1. Tell them to run this in a **separate Terminal window**:
   ```
   claude setup-token
   ```
2. Ask them to paste the token here.
3. Once they paste it, store it in the Keychain:
   ```bash
   /usr/bin/security add-generic-password -a "$USER" -s "whisperbox-claude-oauth" -w "<pasted-token>" -U
   ```
4. Confirm: "Token saved to Keychain."

If they say no or if a token already exists, continue.

### Step 3 — Build the app

Run the build script:

```bash
cd /Users/alexv/Squareflow/WhisperBox/whisper-box && bash app/dev/create-app.command 2>&1
```

Stream the output so the user can follow progress. The build takes 1–3 minutes. Report success or any errors at the end.
