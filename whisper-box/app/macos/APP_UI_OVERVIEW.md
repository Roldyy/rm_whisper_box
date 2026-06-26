# WhisperBox (native macOS) — UI Overview for Design Review

A native SwiftUI macOS app: record system+mic audio, transcribe locally (WhisperKit),
and optionally summarize with Claude. Layout is a `NavigationSplitView` (sidebar +
detail) plus a `MenuBarExtra`. All copy is **French**. Styling is currently **stock
SwiftUI** (system colors, SF Symbols, `.formStyle(.grouped)`, monospaced transcript
text) — no custom theme, branding, or app icon yet.

## Sidebar sections
`Enregistrer · Transcrire · Historique · Journaux · Réglages` (SF Symbols icons).

## Screens

### 1. Enregistrer (Record)
- Large monospaced **timer** (red while recording).
- Toggles: **Inclure le micro**, **Transcription en direct** (disabled while recording).
- Buttons (state-driven, `.borderedProminent`): **Démarrer** → **Pause / Arrêter** → **Reprendre / Arrêter**.
- **"Transcription en direct"** panel: live transcript text streaming in (~30s chunks) while recording.
- Error text; "stopped by sleep" notice.

### 2. Transcrire (Transcribe)
- Text field for a file path + **Parcourir…** (native file picker) + **Transcrire**.
- **Progress bar** + status ("Transcription… NN%").
- **"Aperçu en direct"** panel: cumulative live text.
- **Segments list**: `[mm:ss] text` monospaced.
- After success: **Résumé Claude** button + summary panel.

### 3. Historique (History)
- **"En cours"** section: per running job — progress bar, %, live-text snippet, **Annuler**.
- **"Terminés"** section: rows with a **mic/doc icon** (recording vs file), filename, date, colored status (Terminé/Erreur/Annulé).
- Tap a row → **detail sheet**: full selectable transcript, Claude summary, and buttons: **Exporter la transcription**, **Exporter le résumé**, **Résumé Claude**, **Ouvrir**.
- Right-click menu: detail, open transcript, reveal in Finder, open recording/audio, open summary, export transcript/summary, Résumé Claude, re-transcrire (haute qualité), supprimer.

### 4. Journaux (Logs)
- List of jobs: filename, status, **error message (red)**, model, timestamp. Debug-oriented.

### 5. Réglages (Settings)
- **Transcription**: model (fixed: large-v3-turbo), **output format** picker (txt/srt/vtt).
- **Claude**: enable toggle, model picker (Opus 4.8 / Sonnet 4.6 / Haiku 4.5), auto-summary toggle.
- **Prompt Claude**: multiline `TextEditor` (editable instruction) + Réinitialiser.
- **Jeton Claude**: secure field + Enregistrer / Effacer + "token présent" indicator.

### Menu bar (`MenuBarExtra`)
- Icon flips to a red dot while recording.
- Recording controls (Démarrer / Pause / Reprendre / Arrêter), elapsed time, running-transcription count, Quitter.

## Known design gaps / opportunities (candidates for a redesign)
- No app icon, branding, or accent color; everything is system-default.
- Record screen could be more focused/hero (it's the primary action).
- Inconsistent use of `List` vs `Table`; spacing/hierarchy is ad hoc.
- Empty states exist only on History/Logs.
- Transcribe vs Record have overlapping "live panel" patterns that could be unified into one component.
- Detail sheet is functional but plain; status colors/badges could be a shared component.
- No light/dark-mode-specific tuning or typography scale.

## How to use this for a design pass
1. Run the app and **screenshot each tab** (Record idle + recording, Transcribe running, History with En cours + detail sheet, Settings).
2. Share this doc + the screenshots with Claude (claude.ai) and ask for a redesign / component system / visual hierarchy proposal.
3. Bring the suggestions back here and I'll implement them in SwiftUI.
