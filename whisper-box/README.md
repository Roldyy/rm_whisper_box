# WB — Whisper Box

Interface graphique macOS locale pour transcrire des fichiers audio/vidéo via [OpenAI Whisper](https://github.com/openai/whisper). Traitement 100% local, aucune donnée envoyée dans le cloud.

## Prérequis

- **macOS 12.0+** (Monterey ou supérieur)
- **Homebrew** — [brew.sh](https://brew.sh)
- **Python 3.9+** via Homebrew : `brew install python`
- **Node.js LTS** : `brew install node`
- **ffmpeg** : `brew install ffmpeg`

## Installation

```bash
# 1. Cloner le dépôt
git clone https://github.com/squareflow/whisper-box.git
cd whisper-box

# 2. Rendre les scripts exécutables
chmod +x app/dev/*.command

# 3. Construire et empaqueter l'application
./app/dev/create-app.command
```

Après l'étape 3, double-cliquer sur `WB - Whisper Box.app` dans le dossier du projet.

## Utilisation en mode développement

```bash
./app/dev/launch.command
```

L'app démarre, ouvre le navigateur sur `http://127.0.0.1:7843` et installe une icône dans la menu bar.

## Structure des données

Toutes les données sont stockées dans `~/Whisper Memory/` :

```
~/Whisper Memory/
├── app.db                  — base SQLite (jobs, logs, paramètres)
└── transcripts/            — fichiers de transcription générés
```

Ce dossier n'est jamais touché par `git` et ne contient aucune donnée du dépôt.

## Modèles disponibles

| Modèle | Taille | VRAM | Vitesse (CPU) | Qualité |
|--------|--------|------|----------------|---------|
| tiny   | 39 Mo  | ~1 Go | ~10x temps réel | Basique |
| base   | 74 Mo  | ~1 Go | ~7x temps réel  | Correcte (défaut) |
| small  | 244 Mo | ~2 Go | ~4x temps réel  | Bonne |
| medium | 769 Mo | ~5 Go | ~2x temps réel  | Très bonne |
| large  | 1,5 Go | ~10 Go| ~1x temps réel  | Meilleure |

Sur Apple Silicon (M1/M2/M3), le backend utilise automatiquement MPS pour accélérer le traitement.

## Formats de sortie supportés

`txt`, `srt`, `vtt`, `json`, `tsv`

## Formats audio/vidéo supportés

`mp3`, `mp4`, `wav`, `m4a`, `ogg`, `flac`, `webm`, `mkv`, `avi`, `mov`, `aac`

## Scripts de développement

| Script | Rôle |
|--------|------|
| `app/dev/create-app.command` | Build frontend + empaquetage `.app` complet |
| `app/dev/launch.command` | Démarrage en mode dev (sans bundle) |
| `app/dev/rebuild-frontend.command` | Rebuild React uniquement |
| `app/dev/rebuild-backend.command` | Réinstallation des dépendances Python |
| `app/dev/make-icns.command` | Génère `icon.icns` depuis `icon.png` (requiert macOS) |

## Backend

- **FastAPI** sur `127.0.0.1:7843`
- **SQLite** via SQLAlchemy async
- **rumps** pour l'icône menu bar (main thread / NSRunLoop)
- **uvicorn** dans un thread daemon secondaire
