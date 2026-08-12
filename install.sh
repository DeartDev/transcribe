#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$PROJECT_ROOT"

usage() {
  cat <<'USAGE'
Uso: ./install.sh [--download-model] [--skip-build] [--skip-security-check]

Verifica requisitos, crea directorios del proyecto, construye la imagen Docker y
ejecuta validaciones de seguridad. No instala Docker ni dependencias en Fedora.
USAGE
}

DOWNLOAD_MODEL=0
SKIP_BUILD=0
SKIP_SECURITY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --download-model) DOWNLOAD_MODEL=1 ;;
    --skip-build) SKIP_BUILD=1 ;;
    --skip-security-check) SKIP_SECURITY=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: argumento desconocido: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

require_docker() {
  command -v docker >/dev/null 2>&1 || { echo "ERROR: docker no está instalado o no está en PATH." >&2; exit 1; }
  docker compose version >/dev/null 2>&1 || { echo "ERROR: Docker Compose no está disponible." >&2; exit 1; }
  if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Docker no está accesible para este usuario. No se usará sudo ni se modificará Fedora." >&2
    echo "Revise permisos de /var/run/docker.sock o ejecute desde un usuario con acceso a Docker." >&2
    exit 1
  fi
}

require_docker
mkdir -p audios resultados data/models cache scripts docs src
: > audios/.gitkeep
: > resultados/.gitkeep
: > data/models/.gitkeep
: > cache/.gitkeep
chmod u+rwX audios resultados data data/models cache

export TRANSCRIPTOR_UID="$(id -u)"
export TRANSCRIPTOR_GID="$(id -g)"

echo "Validando configuración Compose..."
docker compose config >/dev/null

if [[ "$SKIP_BUILD" == 0 ]]; then
  echo "Construyendo imagen Docker del proyecto..."
  docker compose build transcriber
else
  echo "Omitiendo build por --skip-build."
fi

if [[ "$SKIP_SECURITY" == 0 ]]; then
  echo "Ejecutando auditoría de seguridad..."
  ./scripts/verify-security.sh
else
  echo "Omitiendo auditoría por --skip-security-check."
fi

if [[ "$DOWNLOAD_MODEL" == 1 ]]; then
  echo "Descargando modelo large-v3..."
  ./scripts/download-model.sh
else
  if [[ -f "$PROJECT_ROOT/data/models/large-v3/.complete.json" ]]; then
    echo "Modelo large-v3 ya disponible en ./data/models/large-v3."
  else
    cat <<'NOTICE'
Modelo no descargado automáticamente.
Para descargarlo cuando tenga red disponible ejecute:
  ./scripts/download-model.sh
NOTICE
  fi
fi

cat <<'DONE'

Instalación completada para los pasos ejecutados.

Uso:
  cp /ruta/a/audio.mp3 ./audios/
  ./transcribir.sh ./audios/audio.mp3

Auditoría:
  ./scripts/verify-security.sh

Desinstalación:
  ./uninstall.sh
DONE
