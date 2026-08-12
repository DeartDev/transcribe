#!/usr/bin/env python3
"""CLI de transcripción local con Faster-Whisper.

La transcripción normal carga exclusivamente el modelo persistido en /models/large-v3
 y está diseñada para ejecutarse sin red dentro del contenedor.
"""
from __future__ import annotations

import argparse
import os
import re
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence

DEFAULT_INPUT_ROOT = Path("/input")
DEFAULT_OUTPUT_ROOT = Path("/output")
DEFAULT_MODEL_PATH = Path("/models/large-v3")
SUPPORTED_FORMATS = ("txt", "srt", "vtt", "all")


@dataclass(frozen=True)
class SegmentData:
    start: float
    end: float
    text: str


def seconds_to_hms(seconds: float) -> str:
    total = max(0, int(seconds))
    hours = total // 3600
    minutes = (total % 3600) // 60
    secs = total % 60
    return f"{hours:02d}:{minutes:02d}:{secs:02d}"


def seconds_to_subtitle_time(seconds: float, separator: str) -> str:
    millis_total = max(0, int(round(seconds * 1000)))
    hours = millis_total // 3_600_000
    millis_total %= 3_600_000
    minutes = millis_total // 60_000
    millis_total %= 60_000
    secs = millis_total // 1000
    millis = millis_total % 1000
    return f"{hours:02d}:{minutes:02d}:{secs:02d}{separator}{millis:03d}"


def safe_output_stem(input_path: Path) -> str:
    stem = input_path.stem.strip()
    # Evita nombres problemáticos sin destruir Unicode razonable.
    stem = re.sub(r"[\\/\x00-\x1f\x7f]+", "_", stem)
    stem = stem.strip(" .")
    return stem or "transcripcion"


def assert_path_inside(path: Path, root: Path) -> Path:
    root_resolved = root.resolve(strict=True)
    resolved = path.resolve(strict=True)
    if resolved == root_resolved or root_resolved not in resolved.parents:
        raise ValueError(f"El archivo debe estar dentro de {root_resolved}: {path}")
    return resolved


def assert_no_symlink_escape(path: Path, root: Path) -> None:
    root_resolved = root.resolve(strict=True)
    current = path
    while current != root_resolved and current != current.parent:
        if current.is_symlink():
            raise ValueError(f"No se aceptan symlinks para archivos de audio: {current}")
        current = current.parent


def validate_input(input_path: Path, input_root: Path = DEFAULT_INPUT_ROOT) -> Path:
    if not input_path.exists():
        raise ValueError(f"No existe el archivo de audio: {input_path}")
    assert_no_symlink_escape(input_path, input_root)
    resolved = assert_path_inside(input_path, input_root)
    if not resolved.is_file():
        raise ValueError(f"La entrada no es un archivo regular: {input_path}")
    return resolved


def validate_model(model_path: Path) -> Path:
    resolved = model_path.resolve()
    if not resolved.is_dir():
        raise ValueError(
            "Modelo no encontrado. Ejecute ./scripts/download-model.sh o ./install.sh --download-model antes de transcribir."
        )
    if not (resolved / "model.bin").is_file():
        raise ValueError(f"Modelo incompleto: falta {resolved / 'model.bin'}")
    return resolved


def render_txt(segments: Sequence[SegmentData]) -> str:
    lines = []
    for seg in segments:
        text = seg.text.strip()
        if text:
            lines.append(f"[{seconds_to_hms(seg.start)} - {seconds_to_hms(seg.end)}] {text}")
    return "\n".join(lines) + ("\n" if lines else "")


def render_srt(segments: Sequence[SegmentData]) -> str:
    blocks = []
    counter = 1
    for seg in segments:
        text = seg.text.strip()
        if not text:
            continue
        start = seconds_to_subtitle_time(seg.start, ",")
        end = seconds_to_subtitle_time(seg.end, ",")
        blocks.append(f"{counter}\n{start} --> {end}\n{text}")
        counter += 1
    return "\n\n".join(blocks) + ("\n" if blocks else "")


def render_vtt(segments: Sequence[SegmentData]) -> str:
    blocks = ["WEBVTT"]
    for seg in segments:
        text = seg.text.strip()
        if not text:
            continue
        start = seconds_to_subtitle_time(seg.start, ".")
        end = seconds_to_subtitle_time(seg.end, ".")
        blocks.append(f"{start} --> {end}\n{text}")
    return "\n\n".join(blocks) + "\n"


def formats_to_write(format_name: str) -> list[str]:
    return ["txt", "srt", "vtt"] if format_name == "all" else [format_name]


def atomic_write(path: Path, content: str, force: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and not force:
        raise FileExistsError(f"La salida ya existe: {path}. Use --force para reemplazarla.")
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=str(path.parent), text=True)
    tmp_path = Path(tmp_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(content)
        os.replace(tmp_path, path)
    except Exception:
        try:
            tmp_path.unlink(missing_ok=True)
        finally:
            raise


def write_outputs(segments: Sequence[SegmentData], output_dir: Path, stem: str, format_name: str, force: bool) -> list[Path]:
    renderers = {"txt": render_txt, "srt": render_srt, "vtt": render_vtt}
    written: list[Path] = []
    for fmt in formats_to_write(format_name):
        out = output_dir / f"{stem}.{fmt}"
        atomic_write(out, renderers[fmt](segments), force=force)
        written.append(out)
    return written


def transcribe_audio(
    input_path: Path,
    model_path: Path,
    language: str,
    beam_size: int,
    vad_filter: bool,
    condition_on_previous_text: bool,
    verbose: bool,
) -> list[SegmentData]:
    from faster_whisper import WhisperModel  # import tardío para permitir tests sin dependencia

    try:
        model = WhisperModel(
            str(model_path),
            device="cpu",
            compute_type="int8",
            local_files_only=True,
        )
    except TypeError:
        # Compatibilidad defensiva si cambia la firma; al pasar ruta local existente no debe descargar.
        model = WhisperModel(str(model_path), device="cpu", compute_type="int8")

    segments_iter, info = model.transcribe(
        str(input_path),
        language=language,
        beam_size=beam_size,
        vad_filter=vad_filter,
        condition_on_previous_text=condition_on_previous_text,
    )

    if verbose:
        print(
            f"Idioma detectado: {getattr(info, 'language', 'desconocido')} "
            f"(probabilidad={getattr(info, 'language_probability', 'n/a')})",
            file=sys.stderr,
        )

    # faster-whisper retorna un generador: hay que consumirlo para ejecutar el procesamiento.
    return [SegmentData(float(seg.start), float(seg.end), str(seg.text)) for seg in segments_iter]


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Transcribe audio localmente con Faster-Whisper.")
    parser.add_argument("audio", type=Path, help="Archivo de audio dentro de /input")
    parser.add_argument("--language", default="es", help="Idioma para Faster-Whisper, por defecto es")
    parser.add_argument("--format", choices=SUPPORTED_FORMATS, default="txt", help="Formato de salida")
    parser.add_argument("--model-path", type=Path, default=DEFAULT_MODEL_PATH, help="Ruta local del modelo")
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_ROOT, help="Directorio de salida")
    parser.add_argument("--beam-size", type=int, default=5, help="beam_size de Faster-Whisper")
    parser.add_argument("--no-vad", action="store_true", help="Desactivar vad_filter")
    parser.add_argument("--no-condition", action="store_true", help="Desactivar condition_on_previous_text")
    parser.add_argument("--force", action="store_true", help="Reemplazar salida existente")
    parser.add_argument("--verbose", action="store_true", help="Mostrar detalles técnicos mínimos")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        input_path = validate_input(args.audio)
        model_path = validate_model(args.model_path)
        output_dir = args.output_dir.resolve()
        stem = safe_output_stem(input_path)

        print(f"Procesando: {input_path.name}")
        print("Modelo: large-v3")
        print("Dispositivo: CPU / int8")
        print(f"Formato: {args.format}")

        segments = transcribe_audio(
            input_path=input_path,
            model_path=model_path,
            language=args.language,
            beam_size=args.beam_size,
            vad_filter=not args.no_vad,
            condition_on_previous_text=not args.no_condition,
            verbose=args.verbose,
        )
        written = write_outputs(segments, output_dir, stem, args.format, args.force)
        for path in written:
            print(f"Salida: {path}")
        return 0
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
