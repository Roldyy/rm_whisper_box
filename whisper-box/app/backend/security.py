from pathlib import Path
from config import SUPPORTED_EXTENSIONS, TRANSCRIPTS_DIR


def validate_source_path(path: str) -> Path:
    """
    Resolve absolute path, verify existence and extension.
    Raises ValueError with a readable message on any failure.
    """
    if not path or not path.strip():
        raise ValueError("Le chemin du fichier source ne peut pas être vide.")

    resolved = Path(path).resolve()

    # Basic path traversal guard: resolved must not escape via symlinks to weird places
    # (We just validate it's absolute and exists as a file)
    if not resolved.is_absolute():
        raise ValueError(f"Le chemin doit être absolu : {path}")

    if not resolved.exists():
        raise ValueError(f"Le fichier n'existe pas : {resolved}")

    if not resolved.is_file():
        raise ValueError(f"Le chemin ne pointe pas vers un fichier : {resolved}")

    if resolved.suffix.lower() not in SUPPORTED_EXTENSIONS:
        supported = ", ".join(sorted(SUPPORTED_EXTENSIONS))
        raise ValueError(
            f"Extension non supportée : '{resolved.suffix}'. "
            f"Extensions acceptées : {supported}"
        )

    return resolved


def validate_output_dir(path: str | None) -> Path:
    """
    Return output directory.
    If None or empty → return TRANSCRIPTS_DIR (created if absent).
    Otherwise validate the given path is an existing directory.
    """
    if not path or not path.strip():
        TRANSCRIPTS_DIR.mkdir(parents=True, exist_ok=True)
        return TRANSCRIPTS_DIR

    resolved = Path(path).resolve()

    if not resolved.exists():
        raise ValueError(f"Le dossier de sortie n'existe pas : {resolved}")

    if not resolved.is_dir():
        raise ValueError(f"Le chemin de sortie n'est pas un dossier : {resolved}")

    return resolved
