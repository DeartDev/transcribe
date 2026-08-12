# Desinstalación

Limpieza Docker del proyecto:

```bash
./uninstall.sh
```

Eliminar además modelo o cache:

```bash
./uninstall.sh --remove-model
./uninstall.sh --remove-cache
```

Eliminar resultados solo si lo confirma explícitamente:

```bash
./uninstall.sh --remove-results
```

Los audios originales en `audios/` nunca se eliminan automáticamente. No se usa `docker system prune`, `docker volume prune`, `docker network prune` ni limpiezas globales.
