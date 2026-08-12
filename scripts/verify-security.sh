#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$PROJECT_ROOT"

MODE="dynamic"
if [[ "${1:-}" == "--static" ]]; then
  MODE="static"
elif [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'USAGE'
Uso: ./scripts/verify-security.sh [--static]

Comprueba controles críticos del proyecto. En modo normal crea un contenedor
efímero de auditoría y lo inspecciona; --static solo revisa Dockerfile y Compose.
USAGE
  exit 0
fi

failures=0
CONFIG_FILE="$(mktemp)"
CID=""
cleanup() {
  rm -f "$CONFIG_FILE"
  if [[ -n "$CID" ]]; then
    docker stop "$CID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

ok() { printf '✓ %s\n' "$1"; }
fail() { printf '✗ %s\n' "$1" >&2; failures=$((failures + 1)); }
contains() { [[ "$1" == *"$2"* ]]; }

require_docker_cli() {
  command -v docker >/dev/null 2>&1 || { fail "docker no está en PATH"; return 1; }
  docker compose version >/dev/null 2>&1 || { fail "Docker Compose no está disponible"; return 1; }
}

check_static() {
  require_docker_cli || return
  if docker compose config >"$CONFIG_FILE"; then
    ok "docker compose config es válido"
  else
    fail "docker compose config falla"
    return
  fi

  if grep -Eq '^[[:space:]]+ports:' "$CONFIG_FILE"; then fail "Compose contiene ports:"; else ok "Compose no publica puertos"; fi
  if grep -Eq '^[[:space:]]+privileged:[[:space:]]*true' "$CONFIG_FILE"; then fail "Compose usa privileged:true"; else ok "Compose no usa privileged:true"; fi
  if grep -Eq 'network_mode:[[:space:]]*host' "$CONFIG_FILE"; then fail "Compose usa host networking"; else ok "Compose no usa host networking"; fi
  if grep -q '/var/run/docker.sock' "$CONFIG_FILE"; then fail "Compose monta docker.sock"; else ok "Docker socket no está montado"; fi
  if grep -Eq 'network_mode:[[:space:]]*none' "$CONFIG_FILE"; then ok "Transcripción declara network_mode:none"; else fail "No se encontró network_mode:none"; fi
  if grep -Eq 'read_only:[[:space:]]*true' "$CONFIG_FILE"; then ok "Root filesystem read_only:true declarado"; else fail "read_only:true no declarado"; fi
  if grep -Eq 'cap_drop:|-[[:space:]]*ALL' "$CONFIG_FILE"; then ok "cap_drop ALL declarado"; else fail "cap_drop ALL no declarado"; fi
  if grep -q 'no-new-privileges:true' "$CONFIG_FILE"; then ok "no-new-privileges declarado"; else fail "no-new-privileges no declarado"; fi
  if grep -qE '^[[:space:]]*EXPOSE\b' Dockerfile; then fail "Dockerfile contiene EXPOSE"; else ok "Dockerfile no contiene EXPOSE"; fi
  local script_files=()
  for file in ./*.sh scripts/*.sh; do
    [[ -e "$file" ]] || continue
    [[ "$file" == "scripts/verify-security.sh" ]] && continue
    script_files+=("$file")
  done
  if ((${#script_files[@]})) && grep -qE 'sudo[[:space:]]+docker|--publish|--publish-all|docker[[:space:]].*[[:space:]]-p[[:space:]]|docker system prune|docker volume prune|docker network prune|builder prune' "${script_files[@]}" 2>/dev/null; then
    fail "Scripts contienen patrones prohibidos (sudo/publish/prune global)"
  else
    ok "Scripts no usan sudo docker, publish ni prune global"
  fi
}

inspect_value() {
  docker inspect --format "$1" "$CID"
}

check_dynamic() {
  if ! docker info >/dev/null 2>&1; then
    fail "Docker daemon no accesible para este usuario"
    return
  fi

  export TRANSCRIPTOR_UID="$(id -u)"
  export TRANSCRIPTOR_GID="$(id -g)"

  echo "Creando contenedor efímero de auditoría..."
  CID="$(docker compose run -d --rm --no-deps --entrypoint sh transcriber -c 'mkdir -p /tmp/home /tmp/cache; id -u > /tmp/audit_uid; sleep 120')"
  if [[ -z "$CID" ]]; then
    fail "No se pudo crear contenedor de auditoría"
    return
  fi

  local port_bindings network_mode privileged cap_drop security_opt readonly user uid mounts socket_mount input_rw output_rw models_rw ps_ports
  port_bindings="$(inspect_value '{{json .HostConfig.PortBindings}}')"
  network_mode="$(inspect_value '{{.HostConfig.NetworkMode}}')"
  privileged="$(inspect_value '{{.HostConfig.Privileged}}')"
  cap_drop="$(inspect_value '{{json .HostConfig.CapDrop}}')"
  security_opt="$(inspect_value '{{json .HostConfig.SecurityOpt}}')"
  readonly="$(inspect_value '{{.HostConfig.ReadonlyRootfs}}')"
  user="$(inspect_value '{{.Config.User}}')"
  mounts="$(inspect_value '{{range .Mounts}}{{println .Destination .RW .Source}}{{end}}')"
  uid="$(docker exec "$CID" id -u 2>/dev/null || true)"
  ps_ports="$(docker ps --filter "id=$CID" --format '{{.Ports}}')"

  [[ "$port_bindings" == "{}" || "$port_bindings" == "null" ]] && ok "HostConfig.PortBindings vacío" || fail "HostConfig.PortBindings no está vacío: $port_bindings"
  [[ -z "$ps_ports" ]] && ok "docker ps no muestra puertos publicados" || fail "docker ps muestra puertos: $ps_ports"
  [[ "$network_mode" == "none" ]] && ok "NetworkMode=none en transcripción" || fail "NetworkMode inesperado: $network_mode"
  [[ "$privileged" == "false" ]] && ok "Privileged=false" || fail "Privileged=$privileged"
  contains "$cap_drop" "ALL" && ok "CapDrop incluye ALL" || fail "CapDrop no incluye ALL: $cap_drop"
  contains "$security_opt" "no-new-privileges:true" && ok "no-new-privileges activo" || fail "SecurityOpt inesperado: $security_opt"
  [[ "$readonly" == "true" ]] && ok "Rootfs read-only activo" || fail "ReadonlyRootfs=$readonly"
  [[ -n "$user" && "$user" != "0" && "$uid" != "0" ]] && ok "Usuario no-root activo (Config.User=$user, id=$uid)" || fail "Usuario root detectado (Config.User=$user, id=$uid)"
  contains "$mounts" "/var/run/docker.sock" && socket_mount=1 || socket_mount=0
  [[ "$socket_mount" == 0 ]] && ok "Docker socket no montado" || fail "Docker socket montado"
  input_rw="$(inspect_value '{{range .Mounts}}{{if eq .Destination "/input"}}{{.RW}}{{end}}{{end}}')"
  output_rw="$(inspect_value '{{range .Mounts}}{{if eq .Destination "/output"}}{{.RW}}{{end}}{{end}}')"
  models_rw="$(inspect_value '{{range .Mounts}}{{if eq .Destination "/models"}}{{.RW}}{{end}}{{end}}')"
  [[ "$input_rw" == "false" ]] && ok "/input montado read-only" || fail "/input no está read-only (RW=$input_rw)"
  [[ "$output_rw" == "true" ]] && ok "/output montado read-write" || fail "/output no está RW (RW=$output_rw)"
  [[ "$models_rw" == "true" ]] && ok "/models montado read-write" || fail "/models no está RW (RW=$models_rw)"
}

check_static
if [[ "$MODE" == "dynamic" ]]; then
  check_dynamic
fi

if [[ "$failures" -eq 0 ]]; then
  echo "Auditoría completada sin fallos."
else
  echo "Auditoría finalizó con $failures fallo(s)." >&2
  exit 1
fi
