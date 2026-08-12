# Seguridad

## Threat model básico

- **Escape de contenedor**: mitigado con usuario no-root, `cap_drop: ALL`, `no-new-privileges:true`, rootfs read-only y contenedores efímeros.
- **Acceso innecesario al host**: solo se montan `audios/`, `resultados/` y `data/models/`.
- **Exposición de red**: no existen `ports:` ni `EXPOSE`; la transcripción usa `network_mode:none`.
- **Ejecución root**: Compose ejecuta con `TRANSCRIPTOR_UID:TRANSCRIPTOR_GID` del host o fallback no-root.
- **Filesystem**: `/input` es read-only; `/output` y `/models` son los únicos persistentes RW; `/tmp` es `tmpfs`.
- **Audios sensibles**: ignorados por Git/Docker, no se suben ni se imprimen en logs.
- **Caches**: `HF_HOME` y `XDG_CACHE_HOME` apuntan a rutas controladas, no a `$HOME` de Fedora.
- **Supply chain**: imagen oficial `python:3.12-slim-bookworm`; dependencias Python fijadas en `requirements.txt`; sin `curl|bash`.

## SELinux

Los mounts usan `:Z` para etiquetado privado porque estos directorios pertenecen solo a este proyecto. No se modifica política SELinux ni se recomienda desactivarlo.

## Auditoría manual

```bash
docker compose config
./scripts/verify-security.sh
docker ps --format 'table {{.Names}}\t{{.Ports}}'
docker inspect <container>
docker compose ps
docker compose images
```

Verificar en `docker inspect`: `PortBindings={}`, `Privileged=false`, `CapDrop` incluye `ALL`, `SecurityOpt` incluye `no-new-privileges:true`, `ReadonlyRootfs=true`, `NetworkMode=none` para `transcriber` y ausencia de `/var/run/docker.sock`.
