# Plan Technique: Whisper Box

## Technology Stack
| Couche | Choix | Rationale |
|---|---|---|
| Backend | Python 3.9+, FastAPI, uvicorn | Pattern OTB éprouvé, async natif |
| DB | SQLite via SQLAlchemy async (aiosqlite) | Légère, no-server, même pattern OTB |
| Transcription | openai-whisper 20231117+ | Bibliothèque open-source officielle OpenAI |
| Audio conversion | ffmpeg (prérequis système via Homebrew) | Whisper l'utilise en interne pour convertir les formats |
| Menu bar | rumps 0.4.0 | Binding Python léger vers NSStatusBar macOS |
| Frontend | React 18 + TypeScript + Vite + Tailwind 3 | Pattern OTB identique |
| State | Zustand + TanStack Query v5 | Pattern OTB identique |
| WebSocket | FastAPI built-in (websockets) | Streaming temps réel de la progression |
| Packaging | Script bash `create-app.command` | Pattern OTB identique |
| Python runtime | Homebrew Python 3.9+ (jamais /usr/bin/python3) | TCC macOS requis pour accès fichiers |

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│  WB - Whisper Box.app                                       │
│                                                             │
│  ┌─────────────────┐     ┌─────────────────────────────┐   │
│  │   launcher.py   │────▶│  rumps menu bar process     │   │
│  │  (main entry)   │     │  (NSStatusBar icon)         │   │
│  └────────┬────────┘     └─────────────────────────────┘   │
│           │ starts                                          │
│  ┌────────▼────────────────────────────────────────────┐   │
│  │  FastAPI + uvicorn  (127.0.0.1:7843)                │   │
│  │                                                     │   │
│  │  api/                                               │   │
│  │   ├── transcription.py  (POST /api/transcribe)      │   │
│  │   ├── jobs.py           (GET/DELETE /api/jobs)      │   │
│  │   ├── logs.py           (GET/DELETE /api/logs)      │   │
│  │   ├── settings.py       (GET/POST /api/settings)    │   │
│  │   └── ws.py             (WS /api/ws/{job_id})       │   │
│  │                                                     │   │
│  │  services/                                          │   │
│  │   ├── whisper_runner.py  (ThreadPoolExecutor)       │   │
│  │   └── job_queue.py       (asyncio Queue)            │   │
│  │                                                     │   │
│  │  static/  ◀── React build (Vite)                   │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ~/Whisper Memory/                                          │
│   ├── app.db              (SQLite)                         │
│   └── transcripts/        (fichiers .txt/.srt/.vtt/...)    │
└─────────────────────────────────────────────────────────────┘
```

**Flow transcription:**
1. Frontend POST /api/transcribe → FastAPI crée un `TranscriptionJob` en DB (status=pending)
2. `job_queue.py` reçoit le job, le passe au `whisper_runner.py` dans un thread
3. `whisper_runner.py` appelle `whisper.transcribe()` et émet des progress events
4. Progress events → WebSocket `/api/ws/{job_id}` → Frontend affiche la progression
5. Fin → DB mise à jour (status=success/error), fichier écrit dans `~/Whisper Memory/transcripts/`

---

## Data Model

### Table `transcription_jobs`
```sql
CREATE TABLE transcription_jobs (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    source_path     TEXT NOT NULL,          -- chemin absolu du fichier source
    source_filename TEXT NOT NULL,          -- nom du fichier (pour affichage)
    model           TEXT NOT NULL,          -- tiny/base/small/medium/large
    language        TEXT,                   -- NULL = auto-detect, 'fr'/'en'/etc.
    output_format   TEXT NOT NULL,          -- txt/srt/vtt/json/tsv
    output_path     TEXT,                   -- chemin du fichier de sortie (NULL si en cours)
    status          TEXT NOT NULL DEFAULT 'pending', -- pending/running/success/error/cancelled
    progress        INTEGER DEFAULT 0,      -- 0-100
    duration_audio  REAL,                   -- durée du fichier audio en secondes
    duration_run    REAL,                   -- durée de la transcription en secondes
    error_message   TEXT,                   -- message d'erreur si status=error
    created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

### Table `execution_logs`
```sql
CREATE TABLE execution_logs (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id          INTEGER REFERENCES transcription_jobs(id),
    operation_type  TEXT NOT NULL DEFAULT 'transcription',
    status          TEXT NOT NULL,          -- running/success/error
    log_content     TEXT,                   -- stdout + stderr de Whisper
    created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

### Table `settings`
```sql
CREATE TABLE settings (
    key     TEXT PRIMARY KEY,
    value   TEXT NOT NULL
);
-- Keys: default_model, default_language, default_output_format, default_output_dir
```

---

## API Design

### POST /api/transcribe
Crée un nouveau job de transcription.
```json
Request: {
  "source_path": "/Users/harold/Desktop/reunion.mp3",
  "model": "base",
  "language": null,
  "output_format": "txt",
  "output_dir": null
}
Response: {
  "job_id": 42,
  "status": "pending"
}
```

### GET /api/jobs
Liste les jobs (sans log_content).
Query params: `status`, `limit` (50), `offset` (0), `search` (recherche sur source_filename)
```json
Response: [{
  "id": 42,
  "source_filename": "reunion.mp3",
  "model": "base",
  "language": "fr",
  "output_format": "txt",
  "output_path": "/Users/harold/Whisper Memory/transcripts/reunion_20260616_143000.txt",
  "status": "success",
  "progress": 100,
  "duration_audio": 1847.3,
  "duration_run": 124.5,
  "created_at": "2026-06-16T14:28:00"
}]
```

### GET /api/jobs/{job_id}
Détail complet d'un job.

### DELETE /api/jobs/{job_id}
Supprime un job de l'historique (ne supprime pas le fichier de sortie).

### POST /api/jobs/{job_id}/cancel
Annule un job en cours (status=cancelled).

### POST /api/jobs/{job_id}/rerun
Recrée un nouveau job avec les mêmes paramètres.

### GET /api/logs
Liste les logs (sans content). Query: `status`, `limit`, `offset`.

### GET /api/logs/{log_id}
Log complet avec `log_content`.

### DELETE /api/logs/{log_id}
Supprime un log.

### GET /api/settings
Retourne tous les settings.
```json
{"default_model": "base", "default_language": null, "default_output_format": "txt", "default_output_dir": null}
```

### POST /api/settings
Met à jour un ou plusieurs settings.

### GET /api/health
Health check + version + ffmpeg status.
```json
{"status": "ok", "version": "1.0.0", "ffmpeg_available": true, "ffmpeg_version": "6.1"}
```

### WebSocket /api/ws/{job_id}
Streaming des événements de progression.
```json
// Events emis par le serveur:
{"type": "progress", "percent": 45, "segment": "...texte partiel..."}
{"type": "log", "message": "[Whisper] Processing segment 23/50..."}
{"type": "done", "status": "success", "output_path": "..."}
{"type": "error", "message": "ffmpeg not found in PATH"}
```

---

## Key Technical Decisions

| Décision | Choix | Alternatives | Rationale |
|---|---|---|---|
| Transcription threading | `asyncio.to_thread` wrappant `whisper.transcribe()` | subprocess whisper CLI | In-process = pas de sérialisation, accès direct au modèle en mémoire |
| Modèle en cache | Module-level singleton `_loaded_models = {}` dans whisper_runner.py | Recharger à chaque job | Évite 5-30s de rechargement entre transcriptions |
| Progress tracking | Monkey-patch de `whisper.transcribe` progress callback | Parsing stderr | L'API Whisper n'expose pas de callback officiel — on intercepte via `tqdm` ou patch |
| Menu bar process | `rumps` dans un thread séparé du process uvicorn | PyObjC direct | rumps est plus simple et maintenu ; run en thread daemon |
| Frontend serving | FastAPI StaticFiles sur `/` après build Vite | Serveur séparé | Même pattern OTB, single process |
| Annulation job | Flag partagé `threading.Event` + vérification dans la boucle Whisper | SIGTERM | Whisper n'a pas d'API d'annulation native — flag de coopération |

---

## Directory Structure
```
whisper-box/
├── app/
│   ├── VERSION                         1.0.0
│   ├── backend/
│   │   ├── launcher.py                 Entry point (.app) : démarre FastAPI + rumps
│   │   ├── main.py                     FastAPI app + routes + static
│   │   ├── config.py                   PORT=7843, DATA_DIR=~/Whisper Memory/
│   │   ├── database.py                 SQLAlchemy engine + session + migrations
│   │   ├── security.py                 Path validation helpers
│   │   ├── requirements.txt
│   │   ├── models/
│   │   │   ├── __init__.py
│   │   │   ├── job.py                  TranscriptionJob ORM model
│   │   │   ├── log.py                  ExecutionLog ORM model
│   │   │   └── setting.py              Setting ORM model
│   │   ├── api/
│   │   │   ├── __init__.py
│   │   │   ├── transcription.py        POST /api/transcribe
│   │   │   ├── jobs.py                 CRUD /api/jobs
│   │   │   ├── logs.py                 CRUD /api/logs
│   │   │   ├── settings.py             GET/POST /api/settings
│   │   │   └── ws.py                   WS /api/ws/{job_id}
│   │   └── services/
│   │       ├── __init__.py
│   │       ├── whisper_runner.py       Transcription + progress + model cache
│   │       └── job_queue.py            asyncio Queue + job dispatcher
│   ├── frontend/
│   │   ├── package.json
│   │   ├── tsconfig.json
│   │   ├── vite.config.ts
│   │   ├── tailwind.config.js
│   │   ├── index.html
│   │   └── src/
│   │       ├── main.tsx
│   │       ├── App.tsx
│   │       ├── index.css
│   │       ├── api/
│   │       │   ├── client.ts           axios instance
│   │       │   ├── jobs.ts             API calls jobs
│   │       │   ├── logs.ts             API calls logs
│   │       │   └── settings.ts         API calls settings
│   │       ├── stores/
│   │       │   └── appStore.ts         Zustand global store
│   │       ├── hooks/
│   │       │   └── useTranscriptionWs.ts  WebSocket hook
│   │       ├── pages/
│   │       │   ├── TranscribePage.tsx  Onglet principal
│   │       │   ├── HistoryPage.tsx     Onglet historique
│   │       │   ├── LogsPage.tsx        Onglet logs
│   │       │   └── SettingsPage.tsx    Onglet paramètres
│   │       └── components/
│   │           ├── FileDropZone.tsx    Drag & drop + file picker
│   │           ├── TranscribeForm.tsx  Formulaire options
│   │           ├── JobCard.tsx         Carte job en cours
│   │           ├── ProgressBar.tsx     Barre de progression
│   │           ├── LogViewer.tsx       Panneau de logs scrollable
│   │           ├── HistoryTable.tsx    Tableau historique
│   │           ├── ConfirmDialog.tsx   Modale de confirmation
│   │           └── StatusBadge.tsx     Badge statut coloré
│   ├── packaging/
│   │   └── macos/
│   │       ├── icon.icns
│   │       ├── icon.png
│   │       └── Info.plist.template     Template avec NSUsageDescription keys
│   └── dev/
│       ├── launch.command              Lancement dev (backend + ouvre browser)
│       ├── create-app.command          Build .app macOS
│       ├── rebuild-frontend.command
│       └── rebuild-backend.command
├── WB - Whisper Box.app/               Généré par create-app.command
├── .gitignore
└── README.md
```

---

## Implementation Sequence
1. **Config + DB** — `config.py`, `database.py`, modèles ORM (TranscriptionJob, ExecutionLog, Setting)
2. **Services** — `whisper_runner.py` (sans WebSocket d'abord), `job_queue.py`
3. **API endpoints** — `transcription.py`, `jobs.py`, `logs.py`, `settings.py`
4. **WebSocket** — `ws.py` + intégration dans `whisper_runner.py`
5. **main.py** — assembly FastAPI, static files, CORS
6. **launcher.py** — démarrage uvicorn + rumps menu bar
7. **Frontend** — structure Vite/React, pages, composants, hooks WS
8. **Packaging** — `create-app.command`, Info.plist, icônes
9. **Dev scripts** — `launch.command`, `rebuild-*.command`

---

## Risk Register
| Risque | Probabilité | Impact | Mitigation |
|---|---|---|---|
| Whisper pas de callback progress natif | Certain | Moyen | Intercepter via patch de `tqdm` ou `whisper.transcribe` interne (segment callback) |
| ffmpeg absent sur la machine | Probable | Haut | Health check au démarrage + message explicite dans l'UI |
| Modèles Whisper > 1 GB (large) | Certain | Bas | Avertissement dans l'UI lors de la sélection ; le DL est géré par Whisper nativement |
| TCC bloque l'accès aux fichiers | Possible | Haut | Homebrew Python obligatoire + NSUsageDescription dans Info.plist |
| rumps incompatible Python 3.12+ | Possible | Moyen | Tester avec Python 3.11 en priorité ; fallback PyObjC si nécessaire |
| Annulation Whisper peu fiable | Probable | Bas | Annulation "soft" : on marque cancelled et on laisse la transcription finir (acceptable en V1) |

---

## Research Notes
> ⚠️ Points à vérifier avant implémentation :

1. **Progress callback Whisper** : La lib `openai-whisper` n'expose pas de progress callback officiel. L'approche recommandée est de sous-classer ou patcher `whisper.decode` ou d'utiliser le paramètre `verbose=True` et de capturer stdout. Vérifier le code source de `whisper/transcribe.py` pour la version utilisée.

2. **rumps + threading** : `rumps.App.run()` doit tourner dans le thread principal (NSRunLoop). FastAPI/uvicorn doit donc tourner dans un thread séparé, et non l'inverse. Cf. pattern : `threading.Thread(target=uvicorn.run, ...).start()` puis `rumps.App(...).run()` dans le main thread.

3. **Compatibilité arm64/x86_64** : `openai-whisper` requiert PyTorch. Sur Apple Silicon, utiliser `torch` avec support MPS (Metal). Vérifier que `whisper` sélectionne automatiquement MPS si disponible.
