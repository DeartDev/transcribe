#!/usr/bin/env python3
"""Descarga controlada del modelo Faster-Whisper dentro del directorio del proyecto."""
from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
import time
from pathlib import Path

DEFAULT_MODEL_ID = "Systran/faster-whisper-large-v3"
DEFAULT_TARGET = Path("/models/large-v3")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Descarga un snapshot Hugging Face de Faster-Whisper en /models."
    )
    parser.add_argument("--model-id", default=DEFAULT_MODEL_ID, help="Repositorio HF del modelo")
    parser.add_argument("--revision", default=os.environ.get("MODEL_REVISION", "main"), help="Revision/commit/tag de Hugging Face")
    parser.add_argument("--target", type=Path, default=DEFAULT_TARGET, help="Directorio destino dentro de /models")
    parser.add_argument("--force", action="store_true", help="Re-descargar y reemplazar el modelo existente")
    parser.add_argument("--verbose", action="store_true", help="Mostrar más detalles")
    return parser.parse_args(argv)


def is_complete(target: Path) -> bool:
    marker = target / ".complete.json"
    if not marker.is_file():
        return False
    required = ["model.bin", "config.json"]
    return all((target / name).is_file() for name in required)


def ensure_within_models(path: Path) -> Path:
    resolved = path.resolve()
    models = Path("/models").resolve()
    if resolved != models and models not in resolved.parents:
        raise SystemExit(f"ERROR: el destino debe estar dentro de /models: {path}")
    return resolved


def write_manifest(target: Path, model_id: str, revision: str, snapshot_path: str) -> None:
    manifest = {
        "model_id": model_id,
        "revision": revision,
        "snapshot_path": snapshot_path,
        "downloaded_at_unix": int(time.time()),
        "managed_by": "transcripcion-local-whisper",
    }
    (target / ".complete.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    target = ensure_within_models(args.target)

    if is_complete(target) and not args.force:
        print(f"Modelo ya disponible: {target}")
        return 0

    if target.exists() and not args.force:
        raise SystemExit(
            f"ERROR: {target} existe pero no parece completo. Use --force para reemplazarlo."
        )

    from huggingface_hub import snapshot_download  # import tardío: solo downloader necesita red

    parent = target.parent
    parent.mkdir(parents=True, exist_ok=True)
    tmp = parent / f".download-{target.name}-{os.getpid()}.tmp"
    if tmp.exists():
        shutil.rmtree(tmp)

    print(f"Descargando modelo: {args.model_id}")
    print(f"Revision: {args.revision}")
    print(f"Destino temporal: {tmp}")

    try:
        snapshot_path = snapshot_download(
            repo_id=args.model_id,
            revision=args.revision,
            local_dir=str(tmp),
        )
        write_manifest(tmp, args.model_id, args.revision, snapshot_path)

        if target.exists():
            backup = parent / f".old-{target.name}-{os.getpid()}"
            target.rename(backup)
            try:
                tmp.rename(target)
                shutil.rmtree(backup, ignore_errors=True)
            except Exception:
                if target.exists():
                    shutil.rmtree(target, ignore_errors=True)
                backup.rename(target)
                raise
        else:
            tmp.rename(target)
    finally:
        if tmp.exists():
            shutil.rmtree(tmp, ignore_errors=True)

    print(f"Modelo listo en: {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
