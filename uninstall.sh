#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$PROJECT_ROOT"

usage() {
  cat <<'USAGE'
Uso: ./uninstall.sh [opciones]

Opciones:
  --yes              No preguntar confirmaciones para acciones solicitadas
  --remove-model     Elimina ./data/models (modelo/cache del modelo)
  --remove-cache     Elimina ./cache
  --remove-results   Elimina ./resultados (por defecto se conserva)
  --docker-only      Solo retira contenedores/redes/imagen del proyecto (por defecto)

Nunca elimina ./audios automáticamente y no ejecuta prune global.
USAGE
}

ASSUME_YES=0
REMOVE_MODEL=0
REMOVE_CACHE=0
REMOVE_RESULTS=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y) ASSUME_YES=1 ;;
    --remove-model) REMOVE_MODEL=1 ;;
    --remove-cache) REMOVE_CACHE=1 ;;
    --remove-results) REMOVE_RESULTS=1 ;;
    --docker-only) ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: argumento desconocido: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

confirm() {
  local question="$1"
  if [[ "$ASSUME_YES" == 1 ]]; then
    return 0
  fi
  read -r -p "$question [y/N] " answer
  [[ "$answer" == "y" || "$answer" == "Y" || "$answer" == "yes" || "$answer" == "YES" ]]
}

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  echo "Retirando recursos Docker del proyecto transcripcion..."
  docker compose down --remove-orphans --volumes || true
  docker image rm transcripcion-local-whisper:latest 2>/dev/null || true
else
  echo "Aviso: Docker no está accesible; se omite limpieza Docker." >&2
fi

if [[ "$REMOVE_MODEL" == 1 ]]; then
  if confirm "Eliminar modelo/cache en ./data/models?"; then
    rm -rf -- "$PROJECT_ROOT/data/models"
    mkdir -p "$PROJECT_ROOT/data/models"
    : > "$PROJECT_ROOT/data/models/.gitkeep"
  fi
fi

if [[ "$REMOVE_CACHE" == 1 ]]; then
  if confirm "Eliminar cache del proyecto en ./cache?"; then
    rm -rf -- "$PROJECT_ROOT/cache"
    mkdir -p "$PROJECT_ROOT/cache"
    : > "$PROJECT_ROOT/cache/.gitkeep"
  fi
fi

if [[ "$REMOVE_RESULTS" == 1 ]]; then
  if confirm "Eliminar resultados de transcripción en ./resultados?"; then
    rm -rf -- "$PROJECT_ROOT/resultados"
    mkdir -p "$PROJECT_ROOT/resultados"
    : > "$PROJECT_ROOT/resultados/.gitkeep"
  fi
else
  echo "Resultados conservados por defecto: ./resultados"
fi

echo "Audios conservados siempre: ./audios"
echo "Desinstalación finalizada para las opciones seleccionadas."
