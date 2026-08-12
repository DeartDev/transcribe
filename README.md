# Transcriptor local con Faster-Whisper y Docker

Herramienta CLI pequeña para transcribir audios locales con **Faster-Whisper large-v3** dentro de Docker. El host solo necesita **Linux + Docker**; no instala Python, FFmpeg, CUDA ni paquetes pip en el sistema operativo.

## Arquitectura

```text
Linux host -> Docker -> contenedor efímero
                         Python 3.12 + Faster-Whisper + CTranslate2

audios/ (RO) -> /input -> transcripción CPU/int8 -> /output -> resultados/ (RW)
modelo persistente: data/models/large-v3
```

Hay dos servicios Compose sobre la misma imagen:

- `model-downloader`: tiene red (`bridge`) solo para descargar `Systran/faster-whisper-large-v3`.
- `transcriber`: ejecuta la transcripción con `network_mode: none`, sin puertos, sin Docker socket y como usuario no-root.

## Requisitos

- Host Linux con Docker Engine y Docker Compose ya instalados.
- Usuario con acceso al daemon Docker (`docker info` debe funcionar sin `sudo`).
- Arquitectura esperada/probada: `x86_64`.
- Fedora fue el entorno de referencia inicial, pero no es un requisito exclusivo.
- Espacio suficiente para `large-v3` y RAM suficiente para CPU/int8.

## Instalación

```bash
./install.sh
```

Para descargar el modelo durante instalación:

```bash
./install.sh --download-model
```

Si no descarga el modelo en instalación, hágalo luego con:

```bash
./scripts/download-model.sh
```

## Uso

```bash
cp /ruta/a/audio.mp3 ./audios/
./transcribir.sh ./audios/audio.mp3
```

Formatos:

```bash
./transcribir.sh ./audios/audio.mp3 --format txt
./transcribir.sh ./audios/audio.mp3 --format srt
./transcribir.sh ./audios/audio.mp3 --format vtt
./transcribir.sh ./audios/audio.mp3 --format all
```

Salida por defecto: `./resultados/audio.txt` con timestamps.

## Directorios

- `audios/`: entradas sensibles, montadas read-only.
- `resultados/`: transcripciones generadas.
- `data/models/large-v3/`: modelo persistente.
- `cache/`: caché local opcional del proyecto.

## Seguridad y privacidad

- No hay `ports:` ni `EXPOSE`.
- Transcripción con `network_mode: none`.
- Contenedor efímero (`docker compose run --rm`).
- Usuario no-root alineado con UID/GID del host.
- `cap_drop: ALL`, `no-new-privileges:true`, rootfs `read_only:true` y `/tmp` en `tmpfs`.
- No se monta `/`, `$HOME` ni `/var/run/docker.sock`.
- Los audios no se copian dentro de la imagen y están ignorados por Git/Docker.
- No se usan APIs cloud ni telemetría propia.

## SELinux

Los bind mounts usan etiqueta privada `:Z`, apropiada para directorios dedicados a este proyecto. No desactive SELinux.

## Auditoría

```bash
./scripts/verify-security.sh

docker compose config
docker ps --format 'table {{.Names}}\t{{.Ports}}'
docker compose ps
docker compose images
```

## Actualización

- Dependencias Python: editar `requirements.txt`, reconstruir con `docker compose build --no-cache transcriber` y auditar.
- Imagen base: actualizar `FROM python:3.12-slim-bookworm` en `Dockerfile`, reconstruir y auditar.
- Modelo: `./scripts/download-model.sh --force --revision <revision>`.

## Desinstalación

```bash
./uninstall.sh
```

Opciones:

```bash
./uninstall.sh --remove-model
./uninstall.sh --remove-cache
./uninstall.sh --remove-results   # pregunta salvo --yes
```

`audios/` se conserva siempre y `resultados/` se conserva por defecto.

## Troubleshooting

- `permission denied /var/run/docker.sock`: el usuario no puede acceder a Docker. El proyecto no usará `sudo`; corrija permisos fuera del proyecto.
- `modelo no encontrado`: ejecute `./scripts/download-model.sh` con red disponible.
- Problemas SELinux: mantenga `:Z`, no use `setenforce 0`.
