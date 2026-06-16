# MASTER SPEC — WB · Whisper Box
**Version** : 1.0.0 · **Date** : 2026-06-16  
**Agent cible** : Claude Code  
**Instruction** : lire ce fichier en entier, puis implémenter les phases dans l'ordre. Ne pas improviser au-delà des tâches décrites. Si un point est ambigu, stopper et demander.

---

## PARTIE 1 — CONSTITUTION (règles non négociables)

### Stack approuvée
| Couche | Choix |
|---|---|
| Backend | Python 3.9+, FastAPI, uvicorn[standard] |
| DB | SQLite via SQLAlchemy 2.x async (aiosqlite + greenlet) |
| Transcription | openai-whisper==20231117 (version fixe) |
| Audio | ffmpeg via Homebrew (prérequis système externe) |
| Menu bar macOS | rumps>=0.4.0 |
| Frontend | React 18, TypeScript strict, Vite 5, Tailwind CSS 3 |
| State | Zustand, TanStack Query v5 |
| Icons | lucide-react |
| HTTP client frontend | axios |
| Fonts | @fontsource/geist-sans + @fontsource/geist-mono |

### Stack interdite
| Technologie | Raison |
|---|---|
| Electron | Trop lourd, hors pattern OTB |
| API Whisper cloud OpenAI | Confidentialité — on veut du 100% local |
| `/usr/bin/python3` (Apple) | Hardened Runtime → TCC bloque l'accès aux fichiers |
| SQLAlchemy sync | Bloque la boucle événementielle uvicorn |
| localStorage | Non supporté dans ce contexte |
| async dans rumps.timer | NSRunLoop crash silencieux |

### Règles architecture
- Backend écoute **uniquement** sur `127.0.0.1:7843`
- **rumps.App.run()** DOIT tourner dans le **main thread** (NSRunLoop)
- **uvicorn** tourne dans un **thread daemon** secondaire
- Communication entre thread asyncio et rumps : via `queue.Queue` thread-safe uniquement (jamais `asyncio.Queue`)
- Modèles Whisper mis en cache module-level entre les jobs
- `~/Whisper Memory/` contient toutes les données — jamais dans le repo

### macOS TCC — Info.plist obligatoire
```xml
<key>NSDocumentsFolderUsageDescription</key>
<string>Whisper Box lit les fichiers audio/vidéo depuis votre dossier Documents.</string>
<key>NSDownloadsFolderUsageDescription</key>
<string>Whisper Box lit les fichiers audio/vidéo depuis vos Téléchargements.</string>
<key>NSDesktopFolderUsageDescription</key>
<string>Whisper Box lit les fichiers audio/vidéo depuis votre Bureau.</string>
<key>NSMusicUsageDescription</key>
<string>Whisper Box accède aux fichiers audio dans Musique.</string>
<key>NSMoviesFolderUsageDescription</key>
<string>Whisper Box lit les fichiers vidéo depuis Films.</string>
<key>NSMicrophoneUsageDescription</key>
<string>Whisper Box peut enregistrer depuis votre micro (fonctionnalité future).</string>
<key>LSUIElement</key>
<false/>
```
`LSUIElement = false` → app visible dans le Dock ET dans la menu bar.

---

## PARTIE 2 — SPEC FONCTIONNELLE

### Ce que l'app fait
Interface graphique locale pour transcrire des fichiers audio/vidéo via OpenAI Whisper (exécution 100% locale). L'utilisateur glisse un fichier, choisit ses options, lance et récupère le texte. Historique persistant, logs d'exécution, paramètres mémorisés.

### Formats supportés
mp3, mp4, wav, m4a, ogg, flac, webm, mkv, avi, mov, aac

### Onglets de l'app
1. **Transcrire** — zone de dépôt fichier + options + progression temps réel
2. **Historique** — liste des transcriptions passées, recherche, relancer, supprimer
3. **Logs** — logs d'exécution détaillés par job
4. **Paramètres** — valeurs par défaut + diagnostic ffmpeg + ouverture data dir

### Comportements clés
- Drag & drop OU bouton "Parcourir" OU saisie manuelle d'un chemin absolu
- Modèles : tiny, base (défaut), small, medium, large
- Langues : auto-detect (défaut) + fr, en, nl, de, es, it, pt, ar, zh, ja
- Formats sortie : txt (défaut), srt, vtt, json, tsv
- Dossier sortie défaut : `~/Whisper Memory/transcripts/`
- Nom fichier sortie : `[stem]_YYYYMMDD_HHMMSS.[ext]`
- Barre de progression + logs temps réel via WebSocket pendant transcription
- Bouton "Annuler" (soft-cancel : marque cancelled, laisse le thread finir en V1)
- Icône menu bar : texte `⏳ 45%` si job running, rien sinon
- Quitter via menu bar ou Cmd+Q

### Ce qui est hors scope (V1)
- Enregistrement live microphone
- Transcription batch parallèle
- Traduction du texte
- Édition dans l'app
- Cloud/sync
- Windows/Linux

---

## PARTIE 3 — PLAN TECHNIQUE (avec solutions aux risques validés)

### Structure des fichiers
```
whisper-box/
├── MASTER_SPEC.md                    ← ce fichier
├── app/
│   ├── VERSION                       ← "1.0.0"
│   ├── backend/
│   │   ├── launcher.py               ← entry point .app
│   │   ├── main.py                   ← FastAPI app assembly
│   │   ├── config.py                 ← constantes globales
│   │   ├── database.py               ← SQLAlchemy engine + session + init
│   │   ├── security.py               ← validation chemins fichiers
│   │   ├── requirements.txt
│   │   ├── models/
│   │   │   ├── __init__.py
│   │   │   ├── job.py                ← TranscriptionJob ORM
│   │   │   ├── log.py                ← ExecutionLog ORM
│   │   │   └── setting.py            ← Setting ORM
│   │   ├── api/
│   │   │   ├── __init__.py
│   │   │   ├── transcription.py      ← POST /api/transcribe + cancel + rerun
│   │   │   ├── jobs.py               ← GET/DELETE /api/jobs
│   │   │   ├── logs.py               ← GET/DELETE /api/logs
│   │   │   ├── settings.py           ← GET/POST /api/settings + health
│   │   │   └── ws.py                 ← WS /api/ws/{job_id}
│   │   └── services/
│   │       ├── __init__.py
│   │       ├── whisper_runner.py     ← transcription + progress + MPS
│   │       ├── job_queue.py          ← asyncio Queue + worker
│   │       └── status_bridge.py      ← queue.Queue thread-safe rumps↔asyncio
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
│   │       │   ├── client.ts
│   │       │   ├── jobs.ts
│   │       │   ├── logs.ts
│   │       │   └── settings.ts
│   │       ├── stores/appStore.ts
│   │       ├── hooks/useTranscriptionWs.ts
│   │       ├── pages/
│   │       │   ├── TranscribePage.tsx
│   │       │   ├── HistoryPage.tsx
│   │       │   ├── LogsPage.tsx
│   │       │   └── SettingsPage.tsx
│   │       └── components/
│   │           ├── FileDropZone.tsx
│   │           ├── TranscribeForm.tsx
│   │           ├── ProgressBar.tsx
│   │           ├── LogViewer.tsx
│   │           ├── HistoryTable.tsx
│   │           ├── StatusBadge.tsx
│   │           └── ConfirmDialog.tsx
│   ├── packaging/macos/
│   │   ├── icon.icns
│   │   ├── icon.png
│   │   └── Info.plist.template
│   └── dev/
│       ├── create-app.command
│       ├── launch.command
│       ├── rebuild-frontend.command
│       └── rebuild-backend.command
└── WB - Whisper Box.app/             ← généré par create-app.command
```

### Data model SQLite

**`transcription_jobs`**
```sql
id              INTEGER PRIMARY KEY AUTOINCREMENT
source_path     TEXT NOT NULL          -- chemin absolu source
source_filename TEXT NOT NULL          -- nom affiché
model           TEXT NOT NULL          -- tiny/base/small/medium/large
language        TEXT                   -- NULL = auto
output_format   TEXT NOT NULL          -- txt/srt/vtt/json/tsv
output_path     TEXT                   -- NULL tant que pending/running
status          TEXT NOT NULL DEFAULT 'pending'  -- pending/running/success/error/cancelled
progress        INTEGER DEFAULT 0      -- 0-100
duration_audio  REAL                   -- secondes (ffprobe)
duration_run    REAL                   -- secondes de traitement
device_used     TEXT                   -- cpu/mps (pour info UI)
error_message   TEXT
created_at      DATETIME DEFAULT CURRENT_TIMESTAMP
updated_at      DATETIME DEFAULT CURRENT_TIMESTAMP
```

**`execution_logs`**
```sql
id              INTEGER PRIMARY KEY AUTOINCREMENT
job_id          INTEGER REFERENCES transcription_jobs(id) ON DELETE CASCADE
operation_type  TEXT DEFAULT 'transcription'
status          TEXT NOT NULL          -- running/success/error
log_content     TEXT                   -- stdout+stderr Whisper
created_at      DATETIME DEFAULT CURRENT_TIMESTAMP
```

**`settings`**
```sql
key   TEXT PRIMARY KEY
value TEXT NOT NULL
-- Seeds : default_model='base', default_language='', default_output_format='txt', default_output_dir=''
```

### API endpoints

| Method | Path | Description |
|---|---|---|
| POST | /api/transcribe | Crée un job, l'enqueue |
| GET | /api/jobs | Liste jobs (params: status, search, limit=50, offset=0) |
| GET | /api/jobs/{id} | Détail job |
| DELETE | /api/jobs/{id} | Supprime job (pas le fichier sortie) |
| POST | /api/jobs/{id}/cancel | Soft-cancel |
| POST | /api/jobs/{id}/rerun | Clone + enqueue |
| GET | /api/logs | Liste logs sans content |
| GET | /api/logs/{id} | Log complet avec content |
| DELETE | /api/logs/{id} | Supprime log |
| GET | /api/settings | Tous les settings |
| POST | /api/settings | Upsert settings |
| GET | /api/health | status + version + ffmpeg_available + ffmpeg_version + device |
| WS | /api/ws/{job_id} | Stream progress/log/done/error |

**WebSocket events (JSON)**
```
{"type": "progress", "percent": 45, "segment": "...texte partiel..."}
{"type": "log",      "message": "Segment 12/28 traité"}
{"type": "done",     "status": "success", "output_path": "/Users/.../reunion.txt"}
{"type": "error",    "message": "ffmpeg introuvable dans le PATH"}
```

---

## PARTIE 4 — SOLUTIONS AUX RISQUES TECHNIQUES

### Solution R1 — Progress Whisper (monkey-patch tqdm)

Implémenter EXACTEMENT ce pattern dans `whisper_runner.py` :

```python
import tqdm as tqdm_module
import threading
import time

def _transcribe_with_progress(
    model,
    audio_path: str,
    cancel_event: threading.Event,
    progress_cb,   # callable(percent: int, message: str)
    **whisper_kwargs
) -> dict:
    """
    Intercepte la progression de Whisper via monkey-patch de tqdm.
    Validé sur openai-whisper==20231117.
    """
    original_tqdm = tqdm_module.tqdm

    class _ProgressTqdm(original_tqdm):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, **kwargs)
            self._t0 = time.time()

        def update(self, n=1):
            if cancel_event.is_set():
                raise InterruptedError("Annulé par l'utilisateur")
            super().update(n)
            if self.total and self.total > 0:
                pct = int((self.n / self.total) * 100)
                elapsed = time.time() - self._t0
                eta = (elapsed / self.n * (self.total - self.n)) if self.n > 0 else 0
                progress_cb(pct, f"Segment {self.n}/{self.total} — ETA {eta:.0f}s")

        def set_postfix(self, ordered_dict=None, refresh=True, **kwargs):
            # Whisper stocke le texte partiel ici — on le capture si besoin
            super().set_postfix(ordered_dict, refresh, **kwargs)

    tqdm_module.tqdm = _ProgressTqdm
    try:
        return model.transcribe(audio_path, verbose=False, **whisper_kwargs)
    finally:
        tqdm_module.tqdm = original_tqdm
```

**Note** : `self.total` = nombre de chunks de 30s. Sur un fichier d'1h → ~120 chunks. Acceptable.

Pour la durée audio, utiliser ffprobe (pas librosa) :

```python
import subprocess, json

def get_audio_duration(path: str) -> float | None:
    try:
        r = subprocess.run(
            ["ffprobe", "-v", "quiet", "-print_format", "json", "-show_format", path],
            capture_output=True, text=True, timeout=10
        )
        return float(json.loads(r.stdout)["format"]["duration"])
    except Exception:
        return None
```

---

### Solution R2 — rumps + uvicorn (threading pattern)

Implémenter EXACTEMENT ce pattern dans `launcher.py` :

```python
import threading, queue, time, webbrowser, requests
import uvicorn, rumps

APP_URL = "http://127.0.0.1:7843"

# Bridge thread-safe pour passer le statut de whisper_runner → rumps
# (jamais asyncio.Queue ici — NSRunLoop et asyncio ne se partagent pas)
_status_bridge: queue.Queue = queue.Queue(maxsize=10)

def _start_uvicorn():
    """DOIT tourner dans un thread daemon, jamais dans le main thread."""
    uvicorn.run("main:app", host="127.0.0.1", port=7843,
                log_level="warning", loop="asyncio")

def _wait_for_backend(timeout=30) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            if requests.get(f"{APP_URL}/api/health", timeout=1).status_code == 200:
                return True
        except Exception:
            pass
        time.sleep(0.3)
    return False

class WhisperBoxMenuBar(rumps.App):
    def __init__(self):
        super().__init__("Whisper Box", icon="app/packaging/macos/icon.png",
                         quit_button=None)
        self.menu = [
            rumps.MenuItem("Ouvrir Whisper Box", callback=self._open),
            None,
            rumps.MenuItem("Quitter", callback=lambda _: rumps.quit_application()),
        ]

    def _open(self, _):
        webbrowser.open(APP_URL)

    @rumps.timer(2)
    def _poll_status(self, _):
        """Tourne dans le main thread — lit la queue.Queue, jamais asyncio."""
        try:
            status = _status_bridge.get_nowait()
            if status.get("running"):
                self.title = f"⏳ {status['percent']}%"
            else:
                self.title = None
        except queue.Empty:
            pass

if __name__ == "__main__":
    # 1. uvicorn dans un thread daemon
    threading.Thread(target=_start_uvicorn, daemon=True).start()
    # 2. Attendre le backend
    assert _wait_for_backend(), "Backend non démarré — vérifier les logs"
    # 3. Ouvrir le navigateur
    webbrowser.open(APP_URL)
    # 4. rumps dans le MAIN THREAD (NSRunLoop obligatoire)
    WhisperBoxMenuBar().run()
```

Dans `whisper_runner.py`, pour mettre à jour la menu bar depuis asyncio :

```python
# Import du bridge depuis launcher (ou depuis un module séparé status_bridge.py)
from launcher import _status_bridge  # ou: from services.status_bridge import push_status

def _notify_status(running: bool, percent: int = 0):
    try:
        _status_bridge.put_nowait({"running": running, "percent": percent})
    except queue.Full:
        pass  # drop silencieux si la queue est pleine
```

**Créer `services/status_bridge.py`** (évite l'import circulaire launcher ↔ services) :

```python
# services/status_bridge.py
import queue
_bridge: queue.Queue = queue.Queue(maxsize=10)

def push(running: bool, percent: int = 0):
    try:
        _bridge.put_nowait({"running": running, "percent": percent})
    except queue.Full:
        pass

def poll():
    try:
        return _bridge.get_nowait()
    except queue.Empty:
        return None
```

---

### Solution R3 — PyTorch / Apple Silicon (MPS avec fallback)

Implémenter cette fonction dans `whisper_runner.py` comme point d'entrée unique pour le chargement des modèles :

```python
import torch
import whisper
import logging

logger = logging.getLogger(__name__)
_model_cache: dict[str, whisper.Whisper] = {}

def _detect_device() -> str:
    """MPS si disponible et macOS >= 12.3, sinon CPU."""
    if torch.backends.mps.is_available() and torch.backends.mps.is_built():
        return "mps"
    return "cpu"

def load_model(name: str) -> tuple[whisper.Whisper, str]:
    """
    Charge le modèle Whisper avec device optimal.
    Retourne (model, device_used).
    Cache en mémoire entre les jobs — ne jamais recharger si déjà en cache.
    """
    if name in _model_cache:
        return _model_cache[name], _detect_device()

    device = _detect_device()
    try:
        model = whisper.load_model(name, device=device)
        if device == "mps":
            # Validation rapide : encoder sur MPS (large-v3 peut crasher sur macOS < 14.2)
            with torch.no_grad():
                dummy = torch.zeros(1, 80, 3000).to("mps")
                model.encoder(dummy)
        _model_cache[name] = model
        logger.info("Modèle %s chargé sur %s", name, device)
        return model, device
    except (RuntimeError, AssertionError) as e:
        if device == "mps":
            logger.warning("MPS incompatible avec %s (%s) — fallback CPU", name, e)
            model = whisper.load_model(name, device="cpu")
            _model_cache[name] = model
            return model, "cpu"
        raise
```

Stocker `device_used` dans la colonne `device_used` de `transcription_jobs` et l'afficher dans l'UI (information utile pour le debug perfs).

---

## PARTIE 5 — TASK BREAKDOWN (ordre d'implémentation strict)

> Implémenter dans cet ordre. Marquer chaque tâche complète avant de passer à la suivante.  
> Ne pas passer à la Phase N+1 avant le checkpoint de la Phase N.

---

### PHASE 1 — Fondations

#### T1.1 — config.py + requirements.txt + VERSION
**Fichiers** : `app/backend/config.py`, `app/backend/requirements.txt`, `app/VERSION`, `.gitignore`

`config.py` doit contenir :
```python
APP_PORT = 7843
APP_HOST = "127.0.0.1"
APP_NAME = "WB - Whisper Box"
DATA_DIR = Path.home() / "Whisper Memory"
TRANSCRIPTS_DIR = DATA_DIR / "transcripts"
DB_PATH = DATA_DIR / "app.db"
DATABASE_URL = f"sqlite+aiosqlite:///{DB_PATH}"
CORS_ORIGINS = ["http://127.0.0.1:7843", "http://localhost:7843", "http://localhost:3000"]
SUPPORTED_EXTENSIONS = {".mp3", ".mp4", ".wav", ".m4a", ".ogg", ".flac",
                         ".webm", ".mkv", ".avi", ".mov", ".aac"}
```

`requirements.txt` :
```
fastapi>=0.110.0
uvicorn[standard]>=0.27.0
sqlalchemy[asyncio]>=2.0.0
aiosqlite>=0.19.0
greenlet>=3.0.0
openai-whisper==20231117
python-multipart>=0.0.9
websockets>=12.0
pydantic>=2.0.0
aiofiles>=23.0.0
rumps>=0.4.0
requests>=2.20.0
torch
```

✅ Acceptance : `from config import DATA_DIR, PORT` sans erreur. `pip install -r requirements.txt` OK.

---

#### T1.2 — database.py + modèles ORM
**Fichiers** : `app/backend/database.py`, `app/backend/models/__init__.py`, `app/backend/models/job.py`, `app/backend/models/log.py`, `app/backend/models/setting.py`

`database.py` : engine async, `get_db()` dependency FastAPI, `init_db()` (crée tables + seeds settings).

`models/job.py` : `TranscriptionJob` avec tous les champs du data model (Section 3). Index sur `(status, created_at)`.

`models/log.py` : `ExecutionLog` avec FK `job_id → transcription_jobs.id ON DELETE CASCADE`.

`models/setting.py` : `Setting` key/value. Seeds dans `init_db()` si table vide : `default_model='base'`, `default_language=''`, `default_output_format='txt'`, `default_output_dir=''`.

✅ Acceptance : `python3 -c "import asyncio; from database import init_db; asyncio.run(init_db())"` crée `~/Whisper Memory/app.db` avec 3 tables et 4 settings.

---

#### T1.3 — security.py
**Fichier** : `app/backend/security.py`

```python
def validate_source_path(path: str) -> Path:
    # résout absolu, vérifie existence, vérifie extension dans SUPPORTED_EXTENSIONS
    # lève ValueError avec message lisible sinon

def validate_output_dir(path: str | None) -> Path:
    # si None → TRANSCRIPTS_DIR (créé si absent)
    # sinon valide que c'est un dossier existant
```

✅ Acceptance : chemin `.mp3` existant → OK. Chemin `.pdf` → ValueError. Chemin traversal → ValueError.

---

#### T1.4 — status_bridge.py
**Fichier** : `app/backend/services/status_bridge.py`

Implémenter EXACTEMENT le code de la Solution R2, section `services/status_bridge.py`.

✅ Acceptance : `push(True, 45)` puis `poll()` retourne `{"running": True, "percent": 45}`.

---

**✅ CHECKPOINT PHASE 1** : DB créée, tables OK, seeds OK, validate_source_path testé.

---

### PHASE 2 — Services Backend

#### T2.1 — whisper_runner.py
**Fichier** : `app/backend/services/whisper_runner.py`

Implémenter dans cet ordre :
1. `_detect_device()` — Solution R3
2. `load_model(name)` — Solution R3 (cache + MPS fallback)
3. `get_audio_duration(path)` — Solution R1 (ffprobe)
4. `_transcribe_with_progress(model, path, cancel_event, progress_cb, **kwargs)` — Solution R1 (tqdm patch)
5. `check_ffmpeg() -> tuple[bool, str]` — subprocess `ffprobe -version`
6. `CancellationToken` — wrapper sur `threading.Event`
7. `_active_tokens: dict[int, CancellationToken]`
8. `run_job(job_id, db_session, ws_manager)` — orchestre les étapes :
   - Récupère job depuis DB
   - Status → running, device_used
   - `get_audio_duration()` → duration_audio en DB
   - `load_model(job.model)`
   - `asyncio.to_thread(_transcribe_with_progress, ...)`
   - Écrit le fichier de sortie dans TRANSCRIPTS_DIR
   - Status → success + output_path + duration_run
   - Crée ExecutionLog
   - `status_bridge.push(False)`
9. `cancel_job(job_id)` — set CancellationToken

✅ Acceptance : `check_ffmpeg()` retourne `(True, "6.x")`. `load_model("tiny")` charge sans erreur.

---

#### T2.2 — ws_manager.py
**Fichier** : `app/backend/services/ws_manager.py`

```python
class ConnectionManager:
    # connect(job_id, ws), disconnect(job_id, ws)
    # send_progress(job_id, percent, segment)
    # send_log(job_id, message)
    # send_done(job_id, status, output_path)
    # send_error(job_id, message)
    # Gère silencieusement WebSocketDisconnect
    # Plusieurs connexions WS par job_id supportées
```

✅ Acceptance : envoyer à un job_id sans connexion active → pas d'exception.

---

#### T2.3 — job_queue.py
**Fichier** : `app/backend/services/job_queue.py`

```python
class JobQueue:
    # Singleton asyncio.Queue
    # add_job(job_id: int)
    # start_worker() : coroutine, tourne en fond
    #   → consomme la queue, appelle whisper_runner.run_job()
    #   → exception dans run_job → job status=error, continue sur le suivant
    # get_queue() → dependency FastAPI
```

✅ Acceptance : job ajouté → consommé dans l'ordre FIFO. Exception → worker ne crashe pas.

---

**✅ CHECKPOINT PHASE 2** : `load_model("tiny")` OK. `check_ffmpeg()` OK. Test manuel `run_job` sur un fichier .mp3 court (< 30s).

---

### PHASE 3 — API Endpoints

#### T3.1 — api/transcription.py
**Fichier** : `app/backend/api/transcription.py`

```
POST /api/transcribe
  Body: {source_path, model, language, output_format, output_dir}
  → validate_source_path(), valide model dans MODELS list
  → crée TranscriptionJob en DB (status=pending)
  → job_queue.add_job(job.id)
  → retourne {job_id, status: "pending"}

POST /api/jobs/{job_id}/cancel
  → whisper_runner.cancel_job(), status=cancelled

POST /api/jobs/{job_id}/rerun
  → clone le job (nouveaux timestamps, status=pending)
  → job_queue.add_job(new_job.id)
  → retourne {job_id: new_id, status: "pending"}
```

✅ Acceptance : POST avec chemin inexistant → 422. POST valide → 200 avec job_id.

---

#### T3.2 — api/jobs.py
**Fichier** : `app/backend/api/jobs.py`

```
GET /api/jobs  ?status=&search=&limit=50&offset=0
  → liste paginée, DESC created_at, ilike sur source_filename pour search

GET /api/jobs/{id}   → détail complet

DELETE /api/jobs/{id}  → supprime (cascade log), ne supprime PAS output_path
  → 404 si absent
```

✅ Acceptance : GET retourne liste vide si aucun job. DELETE 999 → 404.

---

#### T3.3 — api/logs.py
**Fichier** : `app/backend/api/logs.py`

```
GET /api/logs  ?status=&limit=50&offset=0
  → liste sans log_content, DESC created_at

GET /api/logs/{id}   → avec log_content

DELETE /api/logs/{id}  → 204, 404 si absent
```

---

#### T3.4 — api/settings.py
**Fichier** : `app/backend/api/settings.py`

```
GET /api/settings   → {default_model, default_language, default_output_format, default_output_dir}

POST /api/settings  Body: {key: value, ...}  → upsert, retourne settings complets

GET /api/health
  → {status: "ok", version: str, ffmpeg_available: bool, ffmpeg_version: str, device: "mps"|"cpu"}
```

---

#### T3.5 — api/ws.py
**Fichier** : `app/backend/api/ws.py`

```
WS /api/ws/{job_id}
  → si job status=success/error : envoyer done/error immédiatement + fermer
  → sinon : enregistrer dans ConnectionManager, stream jusqu'à done/error/disconnect
```

---

#### T3.6 — main.py
**Fichier** : `app/backend/main.py`

```python
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db()
    asyncio.create_task(job_queue.start_worker())
    yield

app = FastAPI(lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=CORS_ORIGINS, ...)

# Monter routers : transcription, jobs, logs, settings, ws
# StaticFiles sur "/" si app/backend/static/ existe
# Catch-all SPA : GET /{full_path:path} → sert index.html
```

✅ Acceptance : `uvicorn main:app --port 7843` démarre. GET /api/health → 200.

---

**✅ CHECKPOINT PHASE 3** : tester tous les endpoints via `/docs` (Swagger UI). Soumettre un job via POST /api/transcribe, suivre via WS /api/ws/{id}.

---

### PHASE 4 — Launcher & Menu Bar

#### T4.1 — launcher.py
**Fichier** : `app/backend/launcher.py`

Implémenter EXACTEMENT le code de la Solution R2. Points critiques :
- `threading.Thread(target=_start_uvicorn, daemon=True).start()` en premier
- `_wait_for_backend()` avant d'ouvrir le browser
- `WhisperBoxMenuBar().run()` dans le main thread en dernier
- `@rumps.timer(2)` lit `status_bridge.poll()` — jamais de code async ici

✅ Acceptance : `python3 launcher.py` → browser s'ouvre sur 7843, icône dans menu bar.

---

**✅ CHECKPOINT PHASE 4** : test end-to-end complet via launcher. Soumettre un .mp3 court, voir progression, icône menu bar animée, résultat dans historique.

---

### PHASE 5 — Frontend React

#### T5.1 — Setup Vite + Tailwind
**Fichiers** : `app/frontend/package.json`, `vite.config.ts`, `tsconfig.json`, `tailwind.config.js`, `index.html`, `src/main.tsx`, `src/index.css`

`package.json` dependencies : react@18, react-dom@18, react-router-dom@6, @tanstack/react-query@5, zustand@4, axios@1, lucide-react, i18next, react-i18next, @fontsource/geist-sans, @fontsource/geist-mono  
devDependencies : typescript@5, vite@5, @vitejs/plugin-react, tailwindcss@3, autoprefixer, postcss

`vite.config.ts` : `build.outDir: '../backend/static'`, proxy `/api` → `http://127.0.0.1:7843`

Palette Tailwind : tons sombres (gray-900 bg principal), accent `violet-500`.

✅ Acceptance : `npm install` + `npm run dev` sur localhost:3000 sans erreur.

---

#### T5.2 — App shell + routing + store
**Fichiers** : `src/App.tsx`, `src/stores/appStore.ts`

`App.tsx` : layout sidebar (4 onglets avec icônes lucide-react) + `<Outlet />` React Router v6.

`appStore.ts` (Zustand) :
```typescript
{
  activeJobId: number | null,
  runningJobs: Map<number, { percent: number, logs: string[] }>,
  settings: Record<string, string>,
  // actions : setActiveJob, updateJobProgress, appendLog, setSettings
}
```

✅ Acceptance : navigation entre les 4 onglets fonctionne.

---

#### T5.3 — API client + hooks
**Fichiers** : `src/api/client.ts`, `src/api/jobs.ts`, `src/api/logs.ts`, `src/api/settings.ts`, `src/hooks/useTranscriptionWs.ts`

`client.ts` : instance axios, baseURL = `window.location.origin`, intercepteur erreur global.

`useTranscriptionWs(jobId: number | null)` :
- Ouvre WS sur `ws://127.0.0.1:7843/api/ws/{jobId}` si jobId non null
- Parse les events JSON, met à jour appStore via les actions
- Ferme la connexion sur unmount ou job done/error

✅ Acceptance : `useJobs({})` retourne les jobs. Hook WS reçoit les events.

---

#### T5.4 — Page Transcrire
**Fichiers** : `src/pages/TranscribePage.tsx`, `src/components/FileDropZone.tsx`, `src/components/TranscribeForm.tsx`, `src/components/ProgressBar.tsx`, `src/components/LogViewer.tsx`

`FileDropZone` :
- Zone HTML5 drag & drop (events `onDragOver`, `onDrop`)
- Bouton "Parcourir" → `<input type="file" accept=".mp3,.mp4,.wav,...">` (hidden, triggeré par click)
- Champ texte pour saisie manuelle de chemin
- Affiche le nom du fichier sélectionné

`TranscribeForm` : selects modèle/langue/format + bouton "Transcrire" (disabled si pas de fichier ou job running).

`TranscribePage` : assemble, gère état local `{filePath, model, language, format}`, POST /api/transcribe, active le WS hook.

`ProgressBar` : `div` avec `width: {percent}%`, transition CSS smooth.

`LogViewer` : `div` overflow-y-auto, font-mono, auto-scroll vers le bas sur nouveau log.

✅ Acceptance : drag .mp3 → nom affiché. Clic Transcrire → barre progression. Logs temps réel.

---

#### T5.5 — Page Historique
**Fichiers** : `src/pages/HistoryPage.tsx`, `src/components/HistoryTable.tsx`, `src/components/StatusBadge.tsx`, `src/components/ConfirmDialog.tsx`

`HistoryTable` : colonnes Fichier / Modèle / Langue / Format / Durée / Device / Statut / Date / Actions (Ouvrir fichier, Relancer, Supprimer).

"Ouvrir fichier" → appel API GET /api/jobs/{id} pour récupérer output_path, puis ouvrir via un lien ou commande OS (note : dans le browser, on ne peut pas ouvrir directement — prévoir un endpoint `GET /api/jobs/{id}/open` qui appelle `subprocess.run(["open", output_path])` côté backend).

Filtre status (dropdown) + search input (debounce 300ms → query param `search`).

`StatusBadge` : pending=gray, running=blue+pulse animation, success=green, error=red, cancelled=orange.

`ConfirmDialog` : modal simple "Confirmer la suppression ?" avec Oui/Non.

✅ Acceptance : liste affichée. Supprimer → dialog → disparition. Relancer → nouveau job.

---

#### T5.6 — Pages Logs + Paramètres
**Fichiers** : `src/pages/LogsPage.tsx`, `src/pages/SettingsPage.tsx`

`LogsPage` : liste résumée, clic ligne → expand `log_content` (accordion), filtre status, bouton supprimer.

`SettingsPage` :
- Formulaire avec les 4 settings (default_model, default_language, default_output_format, default_output_dir)
- Bouton "Tester ffmpeg" → GET /api/health, affiche version ou erreur
- Bouton "Ouvrir le dossier de données" → endpoint `GET /api/settings/open-data-dir` (backend : `subprocess.run(["open", str(DATA_DIR)])`)
- Ajouter `GET /api/settings/open-data-dir` dans `api/settings.py`

✅ Acceptance : modifier un setting → persiste. Tester ffmpeg → résultat affiché.

---

#### T5.7 — Build frontend
**Commande** : `npm run build` dans `app/frontend/`

✅ Acceptance : build sans erreur TypeScript. `app/backend/static/index.html` existe. GET http://127.0.0.1:7843/ sert l'app.

---

**✅ CHECKPOINT PHASE 5** : test end-to-end complet via browser. Toutes les pages fonctionnelles.

---

### PHASE 6 — Packaging macOS

#### T6.1 — Icône
**Fichiers** : `app/packaging/macos/icon.png` (1024×1024), `app/packaging/macos/icon.icns`

Créer une icône simple (micro + onde sonore) et convertir en `.icns` via :
```bash
mkdir icon.iconset
# Redimensionner en 16, 32, 64, 128, 256, 512, 1024px
# cp icon_NxN.png icon.iconset/icon_NxNx.png (selon convention macOS)
iconutil -c icns icon.iconset
```

✅ Acceptance : `file icon.icns` → "Mac OS X icon".

---

#### T6.2 — Info.plist.template
**Fichier** : `app/packaging/macos/Info.plist.template`

Contenu complet avec substitution `{{VERSION}}` :
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" ...>
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>WB - Whisper Box</string>
  <key>CFBundleIdentifier</key><string>be.squareflow.whisperbox</string>
  <key>CFBundleVersion</key><string>{{VERSION}}</string>
  <key>CFBundleShortVersionString</key><string>{{VERSION}}</string>
  <key>CFBundleExecutable</key><string>WB - Whisper Box</string>
  <key>CFBundleIconFile</key><string>icon</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>LSUIElement</key><false/>
  <!-- + toutes les NSUsageDescription de la Constitution -->
</dict></plist>
```

---

#### T6.3 — create-app.command (pattern OTB)
**Fichier** : `app/dev/create-app.command`

Le script doit :
1. Détecter Homebrew Python (liste de chemins comme dans OTB — éviter `/usr/bin/python3`)
2. `cd app/frontend && npm run build`
3. `pip3 install -r app/backend/requirements.txt`
4. Créer `WB - Whisper Box.app/Contents/MacOS/` + `Resources/`
5. Écrire le script launcher shell dans `Contents/MacOS/WB - Whisper Box` :
   ```bash
   #!/bin/bash
   cd "$(dirname "$0")/../Resources"
   exec /path/to/homebrew/python3 launcher.py
   ```
6. `cp app/packaging/macos/icon.icns Contents/Resources/`
7. `sed "s/{{VERSION}}/$APP_VERSION/g" Info.plist.template > Contents/Info.plist`
8. `chmod +x "Contents/MacOS/WB - Whisper Box"`

✅ Acceptance : `./app/dev/create-app.command` sans erreur. Double-clic → browser s'ouvre.

---

#### T6.4 — Scripts dev
**Fichiers** : `app/dev/launch.command`, `app/dev/rebuild-frontend.command`, `app/dev/rebuild-backend.command`

`launch.command` : `pip3 install -r ...requirements.txt && python3 app/backend/launcher.py`

✅ Acceptance : `./launch.command` démarre l'app en mode dev.

---

**✅ CHECKPOINT FINAL — Validation complète**
- [ ] Double-clic sur `WB - Whisper Box.app` → browser ouvre 7843
- [ ] Icône dans menu bar + Dock
- [ ] Transcrire un fichier .mp3 < 1 minute → fichier .txt créé dans `~/Whisper Memory/transcripts/`
- [ ] Historique affiche le job avec status=success et device=mps ou cpu
- [ ] Logs affichent le contenu
- [ ] Modifier un setting → persiste après redémarrage
- [ ] Accéder à un fichier dans Documents → macOS demande la permission (TCC)
- [ ] Quitter via menu bar → processus proprement arrêté
- [ ] Relancer l'app → historique intact

---

## ANNEXE — Fichier `.gitignore`
```
__pycache__/
*.pyc
*.pyo
.DS_Store
node_modules/
app/backend/static/
app/backend/__pycache__/
app/backend/models/__pycache__/
app/backend/api/__pycache__/
app/backend/services/__pycache__/
WB - Whisper Box.app/
*.egg-info/
.venv/
dist/
```
