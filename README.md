# Instrucciones de uso

Las imágenes referenciadas en los ficheros `docker-compose.yaml` y `docker-compose-cluster.yaml` se encuentran disponibles en Docker Hub.

Si se desea hacer uso del sistema con Zookeeper en modo **standalone**:

```bash
docker compose -f docker-compose.yaml up
```

Si se desea hacer uso del sistema con Zookeeper en modo **cluster**:

```bash
docker compose -f docker-compose-cluster.yaml up
```


*Nota: El fichero `compose-inicial.yaml` se creó en una fase de desarrollo temprana del sistema y no incluye servicios que instancien la aplicación app.py, por lo que se debe hacer manualmente en caso de querer utilizar dicho fichero.* 