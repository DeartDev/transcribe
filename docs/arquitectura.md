# Arquitectura

```text
Fedora 44
   │
   └── Docker Engine
         │
         └── Container efímero
              ├── Python 3.12
              ├── Faster-Whisper 1.2.1
              ├── CTranslate2 4.8.1
              └── large-v3
```

## Flujo de datos

```text
audio RO
   │
   ▼
/input dentro del contenedor
   │
   ▼
Faster-Whisper CPU/int8
   │
   ▼
/output dentro del contenedor
   │
   ▼
resultado RW en ./resultados
```

## Ciclo de vida del modelo

1. `model-downloader` descarga `Systran/faster-whisper-large-v3` con red explícita.
2. El snapshot queda persistido en `data/models/large-v3`.
3. `transcriber` carga esa ruta local con `network_mode:none`.

La imagen es común para ambos servicios, pero las fases se separan para que el uso normal no requiera Internet.
