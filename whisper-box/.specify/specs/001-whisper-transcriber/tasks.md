# Tasks: Whisper Box — 001-whisper-transcriber

> Ordre d'exécution strict. Chaque phase est un checkpoint avant de passer à la suivante.
> Agent recommandé : Claude Code dans le dossier `whisper-box/`

---

## Phase 1 — Foundation : Config, DB, Modèles

### Task 1.1 — Structure du projet et config
**Type**: Create  
**Files**: `app/VERSION`, `app/backend/config.py`, `.gitignore`, `app/backend/requirements.txt`  
**Depends on**: —  
**Parallel**: Non

Ce que doit faire le code :
- `config.py` : PORT=7843, APP_HOST="127.0.0.1", APP_NAME="WB - Whisper Box", DATA_DIR=`~/Whisper Memory/`, TRANSCRIPTS_DIR=DATA_DIR/"transcripts", DB_PATH, DATABASE_URL, CORS_ORIGINS
- Migration de nom de dossier (pattern OTB) si ancien dossier existe
- `VERSION` : "1.0.0"
- `.gitignore` : couvre `*.pyc`, `__pycache__/`, `node_modules/`, `.DS_Store`, `app/backend/static/`, `~/Whisper Memory/` (note : pas dans le repo de toute façon)
- `requirements.txt` : fastapi>=0.110.0, uvicorn[standard]>=0.27.0, sqlalchemy[asyncio]>=2.0.0, aiosqlite>=0.19.0, greenlet>=3.0.0, openai-whisper>=20231117, python-multipart>=0.0.9, websockets>=12.0, pydantic>=2.0.0, aiofiles>=23.0.0, rumps>=0.4.0, torch (sans version pin — Whisper le gère)

Acceptance :
- [ ] `from config import DATA_DIR, PORT` fonctionne sans erreur
- [ ] `DATA_DIR` pointe vers `~/Whisper Memory/`
- [ ] `requirements.txt` installable via `pip install -r requirements.txt`

---

### Task 1.2 — Base de données et migrations
**Type**: Create  
**Files**: `app/backend/database.py`, `app/backend/models/__init__.py`, `app/backend/models/job.py`, `app/backend/models/log.py`, `app/backend/models/setting.py`  
**Depends on**: Task 1.1  
**Parallel**: Non

Ce que doit faire le code :
- `database.py` : engine async SQLAlchemy (aiosqlite), SessionLocal, Base, `get_db()` dependency, `init_db()` qui crée les tables si absentes
- `models/job.py` : `TranscriptionJob` avec tous les champs du data model (plan.md), index sur `status` et `created_at`
- `models/log.py` : `ExecutionLog` avec FK vers `TranscriptionJob.id` (nullable, cascade delete)
- `models/setting.py` : `Setting` key/value ; seed des valeurs par défaut si table vide

Acceptance :
- [ ] `python3 -c "from database import init_db; import asyncio; asyncio.run(init_db())"` crée `~/Whisper Memory/app.db` sans erreur
- [ ] Les 3 tables existent dans la DB après init
- [ ] Les settings par défaut sont insérés (default_model="base", default_language=null, default_output_format="txt")

---

### Task 1.3 — Path validation helper
**Type**: Create  
**Files**: `app/backend/security.py`  
**Depends on**: Task 1.1  
**Parallel**: Oui (avec 1.2)

Ce que doit faire le code :
- `validate_source_path(path: str) -> Path` : résout le chemin absolu, vérifie existence, vérifie extension dans SUPPORTED_EXTENSIONS, lève `ValueError` descriptif sinon
- `SUPPORTED_EXTENSIONS = {".mp3", ".mp4", ".wav", ".m4a", ".ogg", ".flac", ".webm", ".mkv", ".avi", ".mov", ".aac"}`
- `validate_output_dir(path: str | None) -> Path` : si None retourne TRANSCRIPTS_DIR, sinon valide que c'est un dossier existant

Acceptance :
- [ ] Un chemin vers un .mp3 existant retourne un Path valide
- [ ] Un chemin vers un .pdf lève ValueError avec message incluant la liste des formats
- [ ] Un chemin traversal (`../../etc/passwd`) lève ValueError

---

## ✅ Checkpoint Phase 1
Vérifier : DB créée, tables OK, settings seed. `python3 security.py` (test manuel avec quelques chemins).

---

## Phase 2 — Services Backend

### Task 2.1 — Job Queue
**Type**: Create  
**Files**: `app/backend/services/__init__.py`, `app/backend/services/job_queue.py`  
**Depends on**: Task 1.2  
**Parallel**: Oui (avec 2.2)

Ce que doit faire le code :
- `JobQueue` : singleton asyncio Queue
- `add_job(job_id: int)` : ajoute le job_id à la queue
- `start_worker()` : coroutine qui tourne en fond, consomme la queue, appelle `whisper_runner.run_job(job_id)`
- Gestion des erreurs : si `run_job` lève une exception, mettre le job en status=error avec le message
- `get_queue()` : dependency FastAPI retournant l'instance singleton

Acceptance :
- [ ] `asyncio.run(test_queue())` : un job_id ajouté est consommé dans l'ordre FIFO
- [ ] Une exception dans le worker ne fait pas crasher le worker (continue sur le prochain job)

---

### Task 2.2 — Whisper Runner
**Type**: Create  
**Files**: `app/backend/services/whisper_runner.py`  
**Depends on**: Task 1.2, Task 1.3  
**Parallel**: Oui (avec 2.1)

Ce que doit faire le code :
- `_loaded_models: dict[str, whisper.Whisper]` : cache module-level
- `get_model(name: str) -> whisper.Whisper` : charge si absent du cache
- `check_ffmpeg() -> tuple[bool, str]` : vérifie `ffmpeg -version`, retourne (available, version_string)
- `CancellationToken` : simple wrapper sur `threading.Event`
- `_active_tokens: dict[int, CancellationToken]` : map job_id → token
- `run_job(job_id: int, progress_callback: Callable[[int, str], None])` :
  1. Récupère le job depuis DB (synchrone via `asyncio.run` ou dans thread)
  2. Met status=running, updated_at=now
  3. Charge le modèle
  4. Appelle `whisper.transcribe(source_path, language=..., verbose=True)` dans `asyncio.to_thread`
  5. Intercepte les logs via redirection de stdout (ou paramètre `decode_options`)
  6. À la fin : écrit le fichier de sortie, met status=success, crée ExecutionLog
  7. En cas d'erreur : status=error, error_message, crée ExecutionLog
- `cancel_job(job_id: int)` : set le CancellationToken (annulation soft)
- `get_output_filename(source_path: str, format: str) -> Path` : `[stem]_[YYYYMMDD_HHMMSS].[ext]`

**Note sur le progress** : `openai-whisper` utilise `tqdm` en interne. Pour capturer la progression, patcher `tqdm.tqdm` ou utiliser `decode_options={"without_timestamps": False}` et compter les segments. Approche recommandée : override de `tqdm` avant l'appel.

Acceptance :
- [ ] `check_ffmpeg()` retourne `(True, "6.x")` si ffmpeg est installé
- [ ] `get_model("base")` charge le modèle sans erreur (peut prendre 5-10s la 1ère fois)
- [ ] `get_output_filename("/tmp/test.mp3", "txt")` retourne un Path avec le bon format

---

### Task 2.3 — WebSocket Manager
**Type**: Create  
**Files**: `app/backend/services/ws_manager.py`  
**Depends on**: —  
**Parallel**: Oui

Ce que doit faire le code :
- `ConnectionManager` : singleton gérant les connexions WebSocket par `job_id`
- `connect(job_id: int, ws: WebSocket)` : enregistre la connexion
- `disconnect(job_id: int, ws: WebSocket)` : désenregistre
- `send_progress(job_id: int, percent: int, segment: str)` : envoie `{"type": "progress", ...}`
- `send_log(job_id: int, message: str)` : envoie `{"type": "log", ...}`
- `send_done(job_id: int, status: str, output_path: str)` : envoie `{"type": "done", ...}`
- `send_error(job_id: int, message: str)` : envoie `{"type": "error", ...}`
- Gère silencieusement les `WebSocketDisconnect`

Acceptance :
- [ ] Plusieurs connexions WS sur le même job_id reçoivent toutes les mises à jour
- [ ] Un client déconnecté ne fait pas crasher le manager

---

## ✅ Checkpoint Phase 2
Test manuel : importer `whisper_runner`, appeler `check_ffmpeg()`, `get_model("tiny")`.

---

## Phase 3 — API Endpoints

### Task 3.1 — Transcription endpoint
**Type**: Create  
**Files**: `app/backend/api/__init__.py`, `app/backend/api/transcription.py`  
**Depends on**: Phase 2  
**Parallel**: Non

Ce que doit faire le code :
- `POST /api/transcribe` : valide le corps (Pydantic), crée `TranscriptionJob` en DB, ajoute à la queue, retourne `{job_id, status}`
- `POST /api/jobs/{job_id}/cancel` : appelle `whisper_runner.cancel_job()`, met status=cancelled
- `POST /api/jobs/{job_id}/rerun` : clone le job (nouveaux timestamps), ajoute à la queue

Acceptance :
- [ ] POST /api/transcribe avec un chemin inexistant → 422 avec message d'erreur lisible
- [ ] POST /api/transcribe avec un chemin valide → 200 avec job_id

---

### Task 3.2 — Jobs CRUD
**Type**: Create  
**Files**: `app/backend/api/jobs.py`  
**Depends on**: Task 1.2  
**Parallel**: Oui (avec 3.3, 3.4)

Ce que doit faire le code :
- `GET /api/jobs` : liste paginée, filtres status + search (ilike sur source_filename), ordre DESC created_at
- `GET /api/jobs/{job_id}` : détail complet
- `DELETE /api/jobs/{job_id}` : supprime le job (et son log via cascade) — NE supprime pas le fichier de sortie

Acceptance :
- [ ] GET /api/jobs retourne une liste (vide si aucun job)
- [ ] DELETE /api/jobs/999 → 404

---

### Task 3.3 — Logs CRUD
**Type**: Create  
**Files**: `app/backend/api/logs.py`  
**Depends on**: Task 1.2  
**Parallel**: Oui

Identique au pattern `logs.py` de l'OTB — adapter pour `ExecutionLog`.

Acceptance :
- [ ] GET /api/logs retourne une liste sans `log_content`
- [ ] GET /api/logs/{id} retourne le `log_content` complet

---

### Task 3.4 — Settings endpoint
**Type**: Create  
**Files**: `app/backend/api/settings.py`  
**Depends on**: Task 1.2  
**Parallel**: Oui

Ce que doit faire le code :
- `GET /api/settings` : retourne dict de tous les settings
- `POST /api/settings` : met à jour un ou plusieurs settings (upsert)
- `GET /api/health` : retourne status="ok", version, ffmpeg_available, ffmpeg_version

Acceptance :
- [ ] GET /api/settings retourne les 4 settings par défaut
- [ ] POST /api/settings `{"default_model": "small"}` → persiste en DB

---

### Task 3.5 — WebSocket endpoint
**Type**: Create  
**Files**: `app/backend/api/ws.py`  
**Depends on**: Task 2.3  
**Parallel**: Oui

Ce que doit faire le code :
- `WS /api/ws/{job_id}` : accepte la connexion WebSocket, enregistre dans `ConnectionManager`, stream les events jusqu'à done/error/disconnect
- Si le job est déjà terminé (status=success/error), envoyer immédiatement `done` ou `error` et fermer

Acceptance :
- [ ] Une connexion WS sur un job terminé reçoit l'event final immédiatement
- [ ] Une connexion WS sur un job running reçoit les events en temps réel

---

### Task 3.6 — FastAPI main.py
**Type**: Create  
**Files**: `app/backend/main.py`  
**Depends on**: Tasks 3.1–3.5  
**Parallel**: Non

Ce que doit faire le code :
- Crée l'app FastAPI
- Ajoute CORS middleware (origines from config)
- Monte les routers : transcription, jobs, logs, settings, ws
- Monte `StaticFiles` sur `/` depuis `app/backend/static/` (si le dossier existe)
- Route catch-all `GET /{full_path}` → sert `index.html` (SPA routing)
- Lifespan : `init_db()` au démarrage + `start_worker()` de la queue

Acceptance :
- [ ] `uvicorn main:app --port 7843` démarre sans erreur
- [ ] GET http://127.0.0.1:7843/api/health → `{"status": "ok", ...}`

---

## ✅ Checkpoint Phase 3
Tester tous les endpoints via curl ou l'outil HTTP de votre choix. Vérifier le schéma OpenAPI sur `/docs`.

---

## Phase 4 — Launcher et Menu Bar

### Task 4.1 — Launcher principal
**Type**: Create  
**Files**: `app/backend/launcher.py`  
**Depends on**: Task 3.6  
**Parallel**: Non

Ce que doit faire le code :
- Détecte l'environnement (.app vs dev)
- Démarre uvicorn dans un `threading.Thread(daemon=True)`
- Attend que le backend soit prêt (poll GET /api/health avec retries)
- Ouvre `http://127.0.0.1:7843` dans le navigateur par défaut (`webbrowser.open`)
- Démarre `rumps.App("Whisper Box", icon=...).run()` dans le thread principal
  - Menu rumps : "Ouvrir Whisper Box" → webbrowser.open, "---", "Quitter" → rumps.quit_application()
  - Méthode `update_status(self, job_running: bool, percent: int)` appelable depuis whisper_runner

Acceptance :
- [ ] `python3 launcher.py` ouvre le navigateur sur http://127.0.0.1:7843
- [ ] L'icône apparaît dans la barre de menu macOS
- [ ] "Quitter" depuis le menu bar arrête le processus proprement

---

## ✅ Checkpoint Phase 4
Test intégration end-to-end : lancer le launcher, soumettre un fichier .mp3 court via curl, vérifier que le job passe running → success.

---

## Phase 5 — Frontend React

### Task 5.1 — Structure Vite + Tailwind
**Type**: Create  
**Files**: `app/frontend/package.json`, `app/frontend/vite.config.ts`, `app/frontend/tsconfig.json`, `app/frontend/tailwind.config.js`, `app/frontend/index.html`, `app/frontend/src/main.tsx`, `app/frontend/src/index.css`  
**Depends on**: —  
**Parallel**: Oui (avec Phase 3)

Ce que doit faire le code :
- `package.json` : dépendances identiques à l'OTB + react-router-dom
- `vite.config.ts` : build outDir vers `../backend/static`, proxy `/api` → `http://127.0.0.1:7843` en dev
- Tailwind config : palette custom (tons sombres, accent violet/indigo inspiré transcription)
- `index.css` : imports Geist Sans + Geist Mono

Acceptance :
- [ ] `npm install` s'exécute sans erreur
- [ ] `npm run dev` démarre sur localhost:3000

---

### Task 5.2 — App shell + routing + store
**Type**: Create  
**Files**: `app/frontend/src/App.tsx`, `app/frontend/src/stores/appStore.ts`  
**Depends on**: Task 5.1  
**Parallel**: Non

Ce que doit faire le code :
- `App.tsx` : layout avec sidebar nav (4 onglets : Transcrire / Historique / Logs / Paramètres), RouterProvider
- `appStore.ts` (Zustand) : activeJobId, runningJobs (map id→progress), settings (cache local)

Acceptance :
- [ ] Navigation entre les 4 onglets fonctionne
- [ ] Sidebar affiche les onglets avec icônes lucide-react

---

### Task 5.3 — API client + hooks
**Type**: Create  
**Files**: `app/frontend/src/api/client.ts`, `app/frontend/src/api/jobs.ts`, `app/frontend/src/api/logs.ts`, `app/frontend/src/api/settings.ts`, `app/frontend/src/hooks/useTranscriptionWs.ts`  
**Depends on**: Task 5.2  
**Parallel**: Non

Ce que doit faire le code :
- `client.ts` : instance axios avec baseURL depuis `window.location.origin`, intercepteur erreur
- `jobs.ts` : `useJobs(filters)`, `useJob(id)`, `deleteJob(id)`, `rerunJob(id)`, `cancelJob(id)`
- `logs.ts` : `useLogs(filters)`, `useLog(id)`, `deleteLog(id)`
- `settings.ts` : `useSettings()`, `updateSettings(data)`
- `useTranscriptionWs(jobId)` : hook WebSocket qui subscribe aux events progress/log/done/error, met à jour le store

Acceptance :
- [ ] `useJobs()` retourne les jobs depuis l'API (avec loading/error states TanStack Query)
- [ ] `useTranscriptionWs(42)` reçoit les events en temps réel

---

### Task 5.4 — Page Transcrire
**Type**: Create  
**Files**: `app/frontend/src/pages/TranscribePage.tsx`, `app/frontend/src/components/FileDropZone.tsx`, `app/frontend/src/components/TranscribeForm.tsx`, `app/frontend/src/components/ProgressBar.tsx`, `app/frontend/src/components/LogViewer.tsx`  
**Depends on**: Task 5.3  
**Parallel**: Non

Ce que doit faire le code :
- `FileDropZone` : zone drag & drop (HTML5 drag events) + bouton "Parcourir" (input file) + champ texte chemin manuel ; affiche nom du fichier sélectionné
- `TranscribeForm` : sélecteurs modèle/langue/format, bouton "Transcrire", désactivé si pas de fichier
- `TranscribePage` : assemble les composants, gère l'état local, soumet à POST /api/transcribe, connecte le WebSocket
- `ProgressBar` : barre animée 0-100%
- `LogViewer` : zone scrollable avec auto-scroll en bas, monospace, logs colorisés (vert=info, rouge=erreur)

Acceptance :
- [ ] Drag & drop d'un fichier .mp3 → nom du fichier affiché
- [ ] Clic "Transcrire" → barre de progression apparaît
- [ ] Logs en temps réel s'affichent pendant la transcription

---

### Task 5.5 — Page Historique
**Type**: Create  
**Files**: `app/frontend/src/pages/HistoryPage.tsx`, `app/frontend/src/components/HistoryTable.tsx`, `app/frontend/src/components/StatusBadge.tsx`, `app/frontend/src/components/ConfirmDialog.tsx`  
**Depends on**: Task 5.3  
**Parallel**: Oui (avec 5.4)

Ce que doit faire le code :
- `HistoryTable` : tableau avec colonnes Fichier / Modèle / Langue / Format / Durée audio / Durée run / Statut / Date / Actions
- Actions par ligne : Ouvrir (GET output_path via système) / Relancer / Supprimer (avec ConfirmDialog)
- Filtre statut (dropdown) + recherche texte (debounced 300ms)
- `StatusBadge` : badge coloré (pending=gris, running=bleu animé, success=vert, error=rouge, cancelled=orange)

Acceptance :
- [ ] La liste affiche les jobs passés
- [ ] Clic "Supprimer" → ConfirmDialog → suppression → disparition de la ligne

---

### Task 5.6 — Pages Logs et Paramètres
**Type**: Create  
**Files**: `app/frontend/src/pages/LogsPage.tsx`, `app/frontend/src/pages/SettingsPage.tsx`  
**Depends on**: Task 5.3  
**Parallel**: Oui (avec 5.5)

Ce que doit faire le code :
- `LogsPage` : identique à l'OTB LogViewer — liste résumée, clic pour expand log_content, filtre status, supprimer
- `SettingsPage` : formulaire settings (modèle défaut, langue défaut, format défaut, dossier sortie), bouton "Vérifier ffmpeg" qui appelle GET /api/health et affiche le résultat, bouton "Ouvrir le dossier de données"

Acceptance :
- [ ] Modification d'un setting → sauvegarde → rechargement affiche la nouvelle valeur
- [ ] "Vérifier ffmpeg" affiche la version ou un message d'erreur

---

### Task 5.7 — Build frontend
**Type**: Create/Configure  
**Files**: `app/frontend/src/` (final build)  
**Depends on**: Tasks 5.2–5.6  
**Parallel**: Non

- `npm run build` génère les assets dans `app/backend/static/`
- Vérifier qu'aucune erreur TypeScript

Acceptance :
- [ ] `npm run build` s'exécute sans erreur
- [ ] `app/backend/static/index.html` existe après le build
- [ ] GET http://127.0.0.1:7843/ sert l'app React

---

## ✅ Checkpoint Phase 5
Test end-to-end complet : démarrer via launcher.py, glisser un fichier audio, lancer la transcription, voir la progression, consulter l'historique.

---

## Phase 6 — Packaging macOS

### Task 6.1 — Icône macOS
**Type**: Create  
**Files**: `app/packaging/macos/icon.icns`, `app/packaging/macos/icon.png`  
**Depends on**: —  
**Parallel**: Oui

- Créer une icône simple (micro + onde) en PNG 1024×1024
- Convertir en `.icns` via `iconutil` (macOS) ou ImageMagick

Acceptance :
- [ ] `app/packaging/macos/icon.icns` existe et est un fichier ICNS valide

---

### Task 6.2 — Script create-app.command
**Type**: Create  
**Files**: `app/dev/create-app.command`, `app/packaging/macos/Info.plist.template`  
**Depends on**: Task 6.1, Task 5.7  
**Parallel**: Non

Ce que doit faire le script (pattern identique OTB) :
1. Détecter Homebrew Python (éviter `/usr/bin/python3`)
2. `npm run build` dans `app/frontend/`
3. `pip3 install -r app/backend/requirements.txt`
4. Créer `WB - Whisper Box.app/Contents/MacOS/WB - Whisper Box` (script shell launcher)
5. Copier `Info.plist` (depuis template, avec substitution de version)
6. Copier `icon.icns` vers `Contents/Resources/`
7. `chmod +x` sur le launcher shell

`Info.plist.template` doit contenir :
- CFBundleName, CFBundleIdentifier (be.squareflow.whisperbox), CFBundleVersion
- Toutes les NSUsageDescription keys (cf. constitution)
- LSUIElement = true (pas d'icône Dock — l'app vit dans la menu bar)
  OU LSUIElement = false si on veut aussi l'icône Dock — à décider

> ⚠️ Décision : `LSUIElement = false` pour que l'app apparaisse dans le Dock ET dans la menu bar.

Acceptance :
- [ ] `chmod +x app/dev/create-app.command && ./app/dev/create-app.command` s'exécute sans erreur
- [ ] `WB - Whisper Box.app` est créé à la racine du projet
- [ ] Double-clic sur le .app ouvre le navigateur sur http://127.0.0.1:7843

---

### Task 6.3 — Scripts dev
**Type**: Create  
**Files**: `app/dev/launch.command`, `app/dev/rebuild-frontend.command`, `app/dev/rebuild-backend.command`  
**Depends on**: —  
**Parallel**: Oui

- `launch.command` : installe les deps Python, démarre le backend, ouvre le browser (mode dev)
- `rebuild-frontend.command` : `npm run build`
- `rebuild-backend.command` : `pip3 install -r requirements.txt`

Acceptance :
- [ ] `./app/dev/launch.command` démarre l'app en mode dev sans erreur

---

## ✅ Checkpoint Phase 6 — Validation finale
- [ ] L'app se lance via double-clic sur le .app
- [ ] L'icône apparaît dans la barre de menu ET dans le Dock
- [ ] Transcrire un fichier audio court (< 1 min) de bout en bout
- [ ] Le fichier de sortie est créé dans `~/Whisper Memory/transcripts/`
- [ ] L'historique montre le job avec status=success
- [ ] Les logs affichent le contenu complet de la transcription
- [ ] Tenter d'accéder à un fichier dans Documents → macOS demande la permission (TCC)
- [ ] Quitter via le menu bar ferme proprement l'app
- [ ] Relancer l'app → les settings sont persistés, l'historique est intact

---

## Odoo-specific checklist (N/A)
Ce projet n'est pas un module Odoo.

## README.md
**Type**: Create  
**File**: `README.md`  
**Depends on**: Phase 6  
**Parallel**: Non

Contenu : présentation, prérequis (Homebrew, ffmpeg, Python 3.9+), installation en 3 commandes, structure du data directory, modèles Whisper disponibles, comment mettre à jour.
