from pathlib import Path

APP_PORT = 7843
APP_HOST = "127.0.0.1"
APP_NAME = "WB - Whisper Box"

DATA_DIR = Path.home() / "Whisper Memory"
TRANSCRIPTS_DIR = DATA_DIR / "transcripts"
DB_PATH = DATA_DIR / "app.db"
DATABASE_URL = f"sqlite+aiosqlite:///{DB_PATH}"

CORS_ORIGINS = [
    "http://127.0.0.1:7843",
    "http://localhost:7843",
    "http://localhost:3000",
]

SUPPORTED_EXTENSIONS = {
    ".mp3", ".mp4", ".wav", ".m4a", ".ogg", ".flac",
    ".webm", ".mkv", ".avi", ".mov", ".aac",
}

SUPPORTED_MODELS = [
    # Multilingues
    "tiny", "base", "small", "medium", "large", "large-v2", "large-v3", "large-v3-turbo",
    # English-only
    "tiny.en", "base.en", "small.en", "medium.en",
]

WHISPER_MODELS_INFO = {
    "tiny":              {"params": "39M",   "vram": "~1 GB",  "speed": "~32x"},
    "base":              {"params": "74M",   "vram": "~1 GB",  "speed": "~16x"},
    "small":             {"params": "244M",  "vram": "~2 GB",  "speed": "~6x"},
    "medium":            {"params": "769M",  "vram": "~5 GB",  "speed": "~2x"},
    "large":             {"params": "1550M", "vram": "~10 GB", "speed": "1x"},
    "large-v2":          {"params": "1550M", "vram": "~10 GB", "speed": "1x"},
    "large-v3":          {"params": "1550M", "vram": "~10 GB", "speed": "1x"},
    "large-v3-turbo":    {"params": "809M",  "vram": "~6 GB",  "speed": "~8x"},
    "tiny.en":           {"params": "39M",   "vram": "~1 GB",  "speed": "~32x"},
    "base.en":           {"params": "74M",   "vram": "~1 GB",  "speed": "~16x"},
    "small.en":          {"params": "244M",  "vram": "~2 GB",  "speed": "~6x"},
    "medium.en":         {"params": "769M",  "vram": "~5 GB",  "speed": "~2x"},
}

SUPPORTED_LANGUAGES = [
    "", "fr", "en", "nl", "de", "es", "it", "pt", "ar", "zh", "ja"
]

SUPPORTED_OUTPUT_FORMATS = ["txt", "srt", "vtt", "json", "tsv", "md"]

def find_repo_root() -> Path | None:
    """Walk up from this file to find the git repo root (.git directory)."""
    current = Path(__file__).resolve().parent
    for _ in range(8):
        if (current / ".git").exists():
            return current
        current = current.parent
    return None

REPO_ROOT: Path | None = find_repo_root()

# Read version from VERSION file
VERSION_FILE = Path(__file__).parent.parent / "VERSION"
try:
    APP_VERSION = VERSION_FILE.read_text().strip()
except Exception:
    APP_VERSION = "1.0.0"
