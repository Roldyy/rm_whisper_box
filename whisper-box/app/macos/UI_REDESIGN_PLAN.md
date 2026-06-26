# WhisperBox UI Redesign Plan (from the 6 reference mockups)

Goal: bring the native SwiftUI app from stock controls to the polished dark design
in the mockups. Strategy: build a small **design-system layer** (tokens + reusable
components) first, then restyle each screen on top of it. App runs **dark-only**.

## 1. Design tokens (approx. from mockups → `Theme.swift`)

| Token | Value (approx) |
|---|---|
| `bg` (window/content) | near-black `#0B0B0D` |
| `surface` (cards) | `#161719`, border `#2A2B2F` (1px) |
| `sidebarBg` | `#0E0E10` |
| `accent` (selection, progress, primary) | blue `#3B74F2` |
| `recordRed` | `#E8473C` |
| `success` | green `#34C759` · `error` red · `cancelled` gray |
| `textPrimary / secondary / tertiary` | `#F2F2F4` / `#9A9BA0` / `#6E6F75` |
| radius | cards 14 · buttons 8 · chips/pills full |
| section label | 11pt, uppercase, tracked, tertiary |
| timers / timestamps | monospaced |
| card padding | 16–20 |

Apply globally: `.preferredColorScheme(.dark)` + a `Theme` enum of `Color`s.

## 2. Reusable components (`Components/`)
- **Card** — rounded surface + hairline border + padding (used everywhere).
- **SectionLabel** — uppercase tertiary header (Settings/History sections).
- **StatusBadge(status)** — pill: running=blue, Terminé=green, Erreur=red, Annulé=gray.
- **ToggleRow(title, subtitle, isOn)** — card row w/ description + tinted toggle.
- **Chip(label, dotColor?)** — pill ("Sortie système", "Micro inclus").
- **Button styles** — `PrimaryButton` (blue), `SecondaryButton` (gray), `DestructiveButton` (red outline).
- **RecordButton** — large circular dark button w/ red center + ring/glow.
- **Waveform** — animated bars while recording (decorative first; real audio levels later).
- **SegmentRow(timestamp, text)** — blue mono timestamp + text, separators.
- **LivePanel** — header ("… · en direct") + scrolling SegmentRows; **shared by Record + Transcribe**.
- **KeycapHint** — "Astuce — ⌘R pour démarrer".

## 3. Per-screen mapping

### Enregistrer — idle (mockup 1)
Hero **RecordButton** centered → "Prêt à enregistrer" + subtitle → **Card** with two
**ToggleRow**s (mic, live) → source **Chip**s (Sortie système / Micro intégré) →
**KeycapHint**. Wire ⌘R to start.

### Enregistrer — recording (mockup 2)
"ENREGISTREMENT EN COURS" (red, tracked) → huge red mono timer → **Waveform** →
Pause / Arrêter (styled) → status **Chip**s → **LivePanel** (segment table) →
top-right red "Enregistrement" badge.

### Transcrire (mockup 3)
"Transcrire un fichier" + subtitle → **file Card** (doc icon, name, *duration · size ·
path*, Parcourir) → **progress Card** (spinner, %, bar, "Segment X / Y · model", Annuler)
→ two-column **LivePanel** ("Aperçu en direct" | "Segments").
*New data needed:* file size + duration; per-segment count for "X / Y".

### Historique — list (mockup 4)
Title + **search field** (new). **SectionLabel** "EN COURS" → running **Card** (icon,
name, sub, En cours badge, Annuler, progress bar, live snippet). "TERMINÉS" → rows
(icon, name, date·duration, **StatusBadge**, chevron).

### Historique — detail sheet (mockup 5)
Sheet: title + badges (Enregistrement/Terminé) → **tab switcher** Transcription | Résumé
Claude (new — currently stacked) → body text → action bar: **Exporter ▾**, Ouvrir,
Révéler dans le Finder, **Résumé Claude** (primary).

### Réglages (mockup 6)
**SectionLabel** groups: TRANSCRIPTION (Modèle locked-right, Format = **segmented**
Texte/SRT/VTT) · AMÉLIORATION CLAUDE (toggle+sub, model dropdown, auto toggle) ·
PROMPT CLAUDE (mono text area + Réinitialiser) · JETON CLAUDE (secure field +
✓ token présent + Enregistrer/Effacer).

## 4. New things the mockups imply (restyle vs. build)
- **Build:** History search/filter; detail-sheet tabs; file duration+size display; per-segment
  "X / Y" progress; source chips with device names; waveform; ⌘R shortcut + global
  recording indicator (mockup 2 bottom-left).
- **Restyle only:** everything else (existing logic stays; just new presentation).

## 5. Sequencing (each step builds + is reviewable)
1. **Theme + Card/SectionLabel/StatusBadge/Button styles** (foundation; no behavior change).
2. **Settings** (mostly restyle — quickest win, validates the system).
3. **Record** (idle + recording, RecordButton, Waveform, LivePanel).
4. **Transcribe** (reuse LivePanel; add file metadata + segment count).
5. **History** (sections + StatusBadge + search; detail-sheet tabs + action bar).
6. **Polish** (empty states, animations, app icon/branding).

## Open questions
- **Waveform**: decorative animation now, or real audio levels (needs metering from the mixer)?
- **Search** in History: filename only, or also transcript text?
- **"Segment X / Y"**: WhisperKit gives window-based progress, not a clean segment total —
  approximate, or drop the "/ Y"?
- **App icon / brand color**: keep system blue accent, or a WhisperBox brand color?
