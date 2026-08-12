#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$PROJECT_ROOT"

usage() {
  cat <<'USAGE'
Uso: ./transcribir.sh ./audios/archivo.mp3 [opciones]

Opciones:
  --format txt|srt|vtt|all   Formato de salida (por defecto: txt)
  --language CODIGO          Idioma para Faster-Whisper (por defecto: es)
  --force                    Reemplaza salidas existentes
  --verbose                  Muestra detalles técnicos mínimos
  --                         Fin de opciones

La ruta de audio debe estar dentro de ./audios. La transcripción normal se ejecuta
sin red (network_mode:none) y sin puertos publicados.
USAGE
}

require_docker() {
  command -v docker >/dev/null 2>&1 || { echo "ERROR: docker no está instalado o no está en PATH." >&2; exit 1; }
  docker compose version >/dev/null 2>&1 || { echo "ERROR: Docker Compose no está disponible." >&2; exit 1; }
  if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Docker no está accesible para este usuario. No se usará sudo ni se modificará Fedora." >&2
    echo "Revise permisos de /var/run/docker.sock o ejecute desde un usuario con acceso a Docker." >&2
    exit 1
  fi
}

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 2
fi

AUDIO_ARG="$1"
shift
FORMAT="txt"
LANGUAGE="es"
FORCE=0
VERBOSE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --format) shift; FORMAT="${1:?Falta formato}" ;;
    --language) shift; LANGUAGE="${1:?Falta idioma}" ;;
    --force) FORCE=1 ;;
    --verbose) VERBOSE=1 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    *) echo "ERROR: argumento desconocido: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

case "$FORMAT" in
  txt|srt|vtt|all) ;;
  *) echo "ERROR: formato no soportado: $FORMAT" >&2; exit 2 ;;
esac

require_docker
mkdir -p audios resultados data/models cache

AUDIO_ROOT="$(readlink -f -- "$PROJECT_ROOT/audios")"
if [[ ! -e "$AUDIO_ARG" ]]; then
  echo "ERROR: no existe el archivo: $AUDIO_ARG" >&2
  exit 1
fi
INPUT_REAL="$(readlink -f -- "$AUDIO_ARG")"

if [[ ! -f "$INPUT_REAL" ]]; then
  echo "ERROR: la entrada no es un archivo regular: $AUDIO_ARG" >&2
  exit 1
fi
if [[ "$INPUT_REAL" != "$AUDIO_ROOT"/* ]]; then
  echo "ERROR: el audio debe estar dentro de ./audios y no puede escapar por symlink." >&2
  exit 1
fi

MODEL_MARKER="$PROJECT_ROOT/data/models/large-v3/.complete.json"
if [[ ! -f "$MODEL_MARKER" ]]; then
  echo "ERROR: modelo large-v3 no encontrado en ./data/models/large-v3." >&2
  echo "Primero ejecute: ./scripts/download-model.sh" >&2
  echo "o: ./install.sh --download-model" >&2
  exit 1
fi

REL_INPUT="${INPUT_REAL#"$AUDIO_ROOT"/}"
CONTAINER_INPUT="/input/$REL_INPUT"

export TRANSCRIPTOR_UID="$(id -u)"
export TRANSCRIPTOR_GID="$(id -g)"

cmd=(docker compose run --rm --no-deps transcriber /app/src/transcribir.py "$CONTAINER_INPUT" --language "$LANGUAGE" --format "$FORMAT")
[[ "$FORCE" == 1 ]] && cmd+=(--force)
[[ "$VERBOSE" == 1 ]] && cmd+=(--verbose)

"${cmd[@]}"
