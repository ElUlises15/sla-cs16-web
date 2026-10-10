"""Completa build/juego sin borrar archivos existentes; corre en studio Linux."""
from pathlib import Path
import shutil

base = Path('/data/build')
for game in ('valve', 'cstrike'):
    source = base / 'descarga' / game
    if not source.is_dir():
        raise SystemExit(f'Falta {source}')
    destination = base / 'juego' / game
    for file in source.rglob('*'):
        if not file.is_file() or file.suffix.lower() in {'.so', '.dll', '.dylib', '.exe'}:
            continue
        target = destination / file.relative_to(source)
        if not target.exists():
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(file, target)
print('Archivos del juego preparados; descarga conservada para reintentos.')
