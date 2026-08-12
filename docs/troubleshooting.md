# Troubleshooting

## Docker no accesible

Si ve permiso denegado contra `/var/run/docker.sock`, el usuario actual no puede hablar con Docker. Este proyecto no ejecuta `sudo docker` ni cambia grupos; resuelva permisos fuera del proyecto y vuelva a ejecutar.

## Modelo no encontrado

Ejecute con red disponible:

```bash
./scripts/download-model.sh
```

La transcripción normal seguirá offline.

## SELinux

No use `setenforce 0`. Los mounts están definidos con `:Z`; asegúrese de ejecutar desde el directorio del proyecto y de que Docker pueda reetiquetar esos paths.

## Memoria o lentitud

`large-v3` en CPU/int8 puede consumir varios GiB y tardar bastante. Cierre aplicaciones pesadas y pruebe con audios cortos primero.
