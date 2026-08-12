# Uso

Copie el audio al directorio confinado:

```bash
cp ~/Descargas/audio.mp3 ./audios/
```

Transcriba:

```bash
./transcribir.sh ./audios/audio.mp3
```

Formatos soportados:

```bash
./transcribir.sh ./audios/audio.mp3 --format txt
./transcribir.sh ./audios/audio.mp3 --format srt
./transcribir.sh ./audios/audio.mp3 --format vtt
./transcribir.sh ./audios/audio.mp3 --format all
```

Opciones útiles:

```bash
./transcribir.sh ./audios/audio.mp3 --language es --force --verbose
```

Los nombres con espacios, acentos y Unicode se soportan siempre que estén dentro de `audios/`.
