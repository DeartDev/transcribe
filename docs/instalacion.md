# Instalación

```bash
./install.sh
```

El instalador:

1. verifica Docker y Compose;
2. crea `audios/`, `resultados/`, `data/models/` y `cache/`;
3. valida Compose;
4. construye la imagen;
5. ejecuta `scripts/verify-security.sh`;
6. opcionalmente descarga el modelo con `--download-model`.

No instala RPM, pip, Python, FFmpeg ni CUDA en Fedora. Si `docker info` falla por permisos, el instalador aborta y no intenta usar `sudo`.

## Descarga del modelo

```bash
./scripts/download-model.sh
```

Opciones:

```bash
./scripts/download-model.sh --force
./scripts/download-model.sh --revision <revision-o-commit>
```
