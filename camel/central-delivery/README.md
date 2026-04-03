# Central delivery (Quarkus + Camel Quarkus)

Servicio en el namespace **`central`** que consume el topic Kafka **`trigger`** y envía un **POST** al **EventListener** de Tekton (`deployment/pipeline/event-listener.yaml`, namespace **`tf`**) con cuerpo JSON `{"id-edge":"<valor del mensaje>"}`.

Mismo patrón que **edge-manager**: aplicación Quarkus (sin Camel K en runtime), imagen **JVM** publicada en **un solo repositorio Quay** con un **tag** propio.

## Imagen en Quay (solution pattern)

Repo: **`quay.io/<org>/sp-edge-to-cloud-data-pipelines-demo`** — tag para este servicio:

- **`:central-delivery-jvm`** (por defecto)

Variables: **`deployment/sp-demo-images.env.sh`** (`QUAY_ORG`, `SP_QUAY_REPOSITORY`, `CENTRAL_DELIVERY_JVM_TAG`).

## Requisitos previos

- Kafka **Ready** en **`central`** (`deployment/central/kafka.yaml`).
- **Triggers** Tekton aplicados en **`tf`** (`EventListener` `train-model-listener` → servicio **`el-train-model-listener`**).
- Red: el pod debe resolver **`el-train-model-listener.tf.svc`** (DNS del clúster; mismo clúster que `central` y `tf`).

## Desarrollo local

```bash
cd camel/central-delivery
# Ajusta %dev en src/main/resources/application.properties (Kafka route TLS, tekton URL si port-forward).
./mvnw quarkus:dev
```

## Compilar JAR (JVM)

```bash
./mvnw -DskipTests package
```

## Construir y publicar la imagen (manual)

Desde la **raíz del repo** (igual que edge-manager):

```bash
source deployment/sp-demo-images.env.sh
bash deployment/build-push-images.sh central-delivery-jvm
# sin push: SKIP_PUSH=1 bash deployment/build-push-images.sh central-delivery-jvm
# Docker: CONTAINER_ENGINE=docker bash deployment/build-push-images.sh central-delivery-jvm
```

Pasos equivalentes a mano:

```bash
cd camel/central-delivery
source ../../deployment/sp-demo-images.env.sh
./mvnw -DskipTests package
podman build -f src/main/docker/Dockerfile.jvm -t "${SP_IMAGE_CENTRAL_DELIVERY_JVM}" .
podman push "${SP_IMAGE_CENTRAL_DELIVERY_JVM}"
```

## Desplegar en OpenShift

1. Imagen publicada en Quay (o ajusta `image:` en el YAML).
2. Pull secret si el repo es privado.
3. Aplica el manifiesto:

   ```bash
   oc project central
   oc apply -f deployment/central/central-delivery-deployment.yaml
   ```

4. Si tu EventListener tiene otro nombre o namespace, edita la variable de entorno **`TEKTON_EVENTLISTENER_URL`** en el Deployment (o `tekton.eventlistener.url` en `application.properties` y reconstruye).

## Configuración

| Propiedad / env | Uso |
|-----------------|-----|
| `camel.component.kafka.brokers` | Por defecto `my-cluster-kafka-bootstrap:9092` en el pod (namespace `central`). |
| `tekton.eventlistener.url` | URL del listener HTTP Tekton (por defecto `http://el-train-model-listener.tf.svc:8080`). |
| `TEKTON_EVENTLISTENER_URL` | Misma URL vía env en OpenShift (sobrescribe la propiedad). |

## Rutas Camel

`src/main/resources/camel/stream.xml` — ruta `pipeline-trigger`: Kafka `trigger` → POST JSON al EventListener.

## Versiones

- **Quarkus / Camel Quarkus** (platform BOM): **3.20.6** (alineado con `camel/edge-manager`).
- **Java**: **21**.

Ya no se usa **`./mvnw ... -Dquarkus.kubernetes.deploy=true`** (extensión OpenShift retirada; despliegue vía imagen + YAML).
