# Project Constitution: Whisper Box

## Vision
Application desktop macOS locale pour la transcription audio/vidéo via OpenAI Whisper (open-source, exécution locale). Inspirée de l'architecture OTB (Odoo Tool Box) : backend Python FastAPI + frontend React, packagée en .app macOS. Aucun cloud, aucune clé API requise pour la transcription de base.

---

## Code Quality
- Python 3.9+ uniquement (pas de walrus operator ou syntaxe 3.10+ dans le code commun)
- FastAPI avec Pydantic v2 pour tous les modèles de données
- SQLAlchemy 2.x async (aiosqlite) — aucun appel sync à la DB
- TypeScript strict (`strict: true` dans tsconfig) — aucun `any` implicite
- Chaque endpoint API a un schema Pydantic en entrée ET en sortie
- Les tâches longues (transcription) tournent dans un thread pool via `asyncio.to_thread` ou `concurrent.futures.ThreadPoolExecutor` — jamais dans la boucle principale uvicorn
- Aucune logique métier dans les fichiers de routing FastAPI — séparer services/ et api/

---

## Architecture Principles
- **Same-process, localhost-only** : le backend FastAPI sert aussi le frontend buildé (static files). Aucun port exposé sur le réseau sauf configuration explicite.
- **Queue asynchrone** : les jobs de transcription passent par une queue interne (inspirée de `queue.py` OTB) avec statuts pending → running → success/error.
- **Data directory isolé** : `~/Whisper Memory/` contient TOUT — base SQLite, transcriptions générées, logs, settings. Aucun fichier de données dans le répertoire du code source.
- **Menu bar icon** : via `rumps` (Objective-C bridge Python) pour l'icône macOS en barre de menu. Le frontend React tourne dans une WebView ou dans le navigateur par défaut.
- **WebSocket pour le streaming** : la progression de la transcription est streamée en temps réel via WebSocket (pattern identique à OTB).

---

## Technology Stack

### Approuvé
| Couche | Choix |
|---|---|
| Backend | Python 3.9+, FastAPI, uvicorn[standard] |
| DB | SQLite via SQLAlchemy async (aiosqlite) |
| Transcription | openai-whisper (local, open-source) |
| Audio processing | ffmpeg (Homebrew, prérequis externe) |
| Menu bar | rumps >= 0.4.0 |
| Frontend | React 18, TypeScript, Vite, Tailwind CSS 3 |
| State | Zustand, TanStack Query v5 |
| Icons | lucide-react |
| HTTP client | axios |
| Packaging macOS | Script bash `create-app.command` (pattern OTB) |
| Fonts | Geist Sans + Geist Mono (@fontsource) |

### Interdit
| Technologie | Raison |
|---|---|
| Electron | Trop lourd, incompatible avec le pattern OTB ciblé |
| whisper API OpenAI (cloud) | Confidentialité, coût, dépendance réseau — on veut du local |
| `/usr/bin/python3` (Apple Python) | Hardened Runtime → macOS TCC bloque l'accès aux fichiers utilisateur |
| localStorage pour état persistant | Non supporté dans le contexte app ; utiliser SQLite |
| SQLAlchemy sync | Bloque la boucle événementielle uvicorn |
| threading direct dans les handlers FastAPI | Utiliser asyncio.to_thread ou ThreadPoolExecutor |

---

## Performance Requirements
- Démarrage de l'app (cold start) : < 5 secondes jusqu'à "ready" dans le navigateur
- Chargement du modèle Whisper `base` : < 10 secondes (première utilisation)
- Models mis en cache en mémoire entre les jobs (ne pas recharger à chaque transcription)
- Streaming de progression : mise à jour WebSocket toutes les 500ms minimum pendant la transcription
- Base SQLite : requêtes < 100ms pour toutes les opérations de liste/filtre

---

## Security Requirements
- Le backend écoute UNIQUEMENT sur `127.0.0.1` (jamais `0.0.0.0` sans opt-in explicite)
- Aucune donnée audio/vidéo n'est envoyée sur internet (transcription 100% locale)
- Les chemins de fichiers fournis par l'utilisateur sont validés (traversal attack prevention) via `Path.resolve()` + vérification que le fichier existe
- CORS restreint à `http://127.0.0.1:[PORT]` et `http://localhost:3000` (dev uniquement)
- Pas de secrets à stocker pour la V1 (pas de clé API nécessaire)

---

## macOS TCC (Privacy) Requirements
L'Info.plist du .app DOIT contenir ces clés :
```xml
<key>NSDocumentsFolderUsageDescription</key>
<string>Whisper Box lit les fichiers audio/vidéo depuis votre dossier Documents.</string>
<key>NSDownloadsFolderUsageDescription</key>
<string>Whisper Box lit les fichiers audio/vidéo depuis votre dossier Téléchargements.</string>
<key>NSDesktopFolderUsageDescription</key>
<string>Whisper Box lit les fichiers audio/vidéo depuis votre Bureau.</string>
<key>NSMusicUsageDescription</key>
<string>Whisper Box peut accéder aux fichiers audio dans votre bibliothèque Musique.</string>
<key>NSMoviesFolderUsageDescription</key>
<string>Whisper Box peut lire les fichiers vidéo depuis votre dossier Films.</string>
<key>NSMicrophoneUsageDescription</key>
<string>Whisper Box peut enregistrer depuis votre micro pour transcrire en direct (fonctionnalité future).</string>
```
**Utiliser Homebrew Python** (jamais `/usr/bin/python3`) — cf. OTB `create-app.command` pour la détection.

---

## Development Practices
- Branche principale : `main`
- VERSION dans `app/VERSION` au format semver `1.0.0`
- Pas de tests unitaires en V1 (prototype) — ajouter pour V2
- Data directory jamais dans le repo (`.gitignore` couvre `~/Whisper Memory/`)
- Scripts de dev dans `app/dev/` : `launch.command`, `create-app.command`, `rebuild-frontend.command`, `rebuild-backend.command`
- Port par défaut : **7843** (évite conflit avec OTB sur 7842)
