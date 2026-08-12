#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$PROJECT_ROOT"

usage() {
  cat <<'USAGE'
Uso: ./scripts/download-model.sh [--force] [--revision REV] [--verbose]

Descarga Systran/faster-whisper-large-v3 dentro de ./data/models/large-v3.
Requiere red solo durante esta fase. No instala nada en Fedora.
USAGE
}

FORCE=0
REVISION="${MODEL_REVISION:-main}"
VERBOSE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=1 ;;
    --revision) shift; REVISION="${1:?Falta revision}" ;;
    --verbose) VERBOSE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: argumento desconocido: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

require_docker() {
  command -v docker >/dev/null 2>&1 || { echo "ERROR: docker no está instalado o no está en PATH." >&2; exit 1; }
  docker compose version >/dev/null 2>&1 || { echo "ERROR: Docker Compose no está disponible." >&2; exit 1; }
  if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Docker no está accesible para este usuario. No se usará sudo ni se modificará el host." >&2
    echo "Revise permisos de /var/run/docker.sock o ejecute desde un usuario con acceso a Docker." >&2
    exit 1
  fi
}

require_docker
mkdir -p audios resultados data/models cache
: > audios/.gitkeep
: > resultados/.gitkeep
: > data/models/.gitkeep
: > cache/.gitkeep

export TRANSCRIPTOR_UID="$(id -u)"
export TRANSCRIPTOR_GID="$(id -g)"

cmd=(docker compose run --rm --no-deps --build model-downloader /app/src/download_model.py --revision "$REVISION")
[[ "$FORCE" == 1 ]] && cmd+=(--force)
[[ "$VERBOSE" == 1 ]] && cmd+=(--verbose)

"${cmd[@]}"
