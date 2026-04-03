# Edge Manager (Quarkus + Camel Quarkus)

Servicio que vigila el bucket S3 **`{edge}-ready`** en MinIO **central** (p. ej. `edge1-ready`) y copia objetos al bucket **`production`** en MinIO **edge**. Cuando detecta `saved_model.pb`, publica un aviso MQTT.

No requiere **Camel K** en runtime: es una aplicación **Quarkus** empaquetable como JAR o **binario nativo (GraalVM / Mandrel)**.

## Nombres de imagen en Quay (solución *Edge-to-Core Data Pipelines for AI/ML*)

Repo Git de referencia: **`sp-edge-to-cloud-data-pipelines-demo`**. En Quay, **un solo repositorio** con el mismo nombre; cada servicio de la demo usa un **tag** distinto:

`quay.io/<org>/sp-edge-to-cloud-data-pipelines-demo:<componente>-<runtime>`

- Edge Manager (JVM): **`:edge-manager-jvm`** (por defecto). Nativo: **`:edge-manager-native`** (**`BACKLOG.md`**).
- Central delivery (JVM): **`:central-delivery-jvm`** (Kafka → Tekton en `central`; ver **`camel/central-delivery/README.md`**).
- Central feeder (JVM): **`:central-feeder-jvm`** (ingesta ZIP → MinIO + Kafka; ver **`camel/central-feeder/README.md`**).
- Futuros: **`:edge-shopper-jvm`**, etc.
- Otras apps del mismo solution pattern: **`…-edge-shopper`**, **`…-central-feeder`**, etc.

Variables para **`podman`** build / push: **`deployment/sp-demo-images.env.sh`** (`source ../../deployment/sp-demo-images.env.sh` desde `camel/edge-manager`). Por defecto **`QUAY_ORG=cestayg`** y **`CONTAINER_ENGINE=podman`**. Para Docker: `export CONTAINER_ENGINE=docker` antes del `source` o del script de build.

## Requisitos

- MinIO en **central** con bucket `edge1-ready` (u otro `{EDGE_ID}-ready`).
- MinIO en **edge** con bucket `production` (`deployment/edge/minio.yaml` + `minio-edge-buckets.sh`).
- Acceso desde edge a MinIO central: **Skupper** (`minio-central` en el namespace edge) o ruta directa (ajustar propiedades).
- **MQTT** AMQ en edge (`broker-amq-mqtt-0-svc:1883`) para el aviso opcional.

## Desarrollo local (JVM)

```bash
cd camel/edge-manager
# Edita src/main/resources/application.properties → perfiles %dev (rutas MinIO, MQTT).
./mvnw quarkus:dev
```

## Compilar JAR (JVM)

```bash
./mvnw -DskipTests package
# Artefacto: target/quarkus-app/quarkus-run.jar
```

## Compilar nativo (GraalVM / Mandrel)

Sin instalar Graal localmente (usa contenedor de Quarkus):

```bash
./mvnw -DskipTests -Dnative -Dquarkus.native.container-build=true package
# Binario: target/manager-1.0.0-runner
```

Con GraalVM/Mandrel instalados localmente:

```bash
./mvnw -DskipTests -Dnative package
```

## Imagen de contenedor y Quay.io

**Por defecto (JVM):** más rápido de compilar; portable entre arquitecturas. Desde la raíz del repo:

```bash
bash deployment/build-push-images.sh
# o explícito:
bash deployment/build-push-images.sh edge-manager-jvm
# sin push: SKIP_PUSH=1 bash deployment/build-push-images.sh edge-manager-jvm
# Docker: CONTAINER_ENGINE=docker bash deployment/build-push-images.sh edge-manager-jvm
```

**GraalVM nativo** (lento; reservado para más adelante — **`BACKLOG.md`**):

```bash
bash deployment/build-push-images.sh edge-manager-native
```

**Manual** (JVM): mismos pasos que `edge_manager_jvm` en **`deployment/build-push-images.sh`**; variables en **`deployment/sp-demo-images.env.sh`**.

En Quay, crea **un** repositorio **`sp-edge-to-cloud-data-pipelines-demo`** bajo tu organización. Los `podman push` suben tags distintos al mismo repo (`SP_QUAY_REPOSITORY` en **`deployment/sp-demo-images.env.sh`**).

## Despliegue manual en OpenShift (`edge1`)

1. Publica la imagen en Quay (o usa una imagen local con `oc import-image` / registry interno).
2. Crea pull secret si el repo es privado: `oc create secret docker-registry quay-cestayg ...` y `serviceAccount` + `imagePullSecrets` (opcional en el Deployment).
3. Aplica el manifiesto (edita la imagen si no usas el tag por defecto):

   ```bash
   oc project edge1
   oc apply -f ../../deployment/edge/edge-manager-deployment.yaml
   ```

4. Asegura **Skupper** y el servicio **`minio-central`** en `edge1`. Los endpoints S3 van por separado: **`camel.uri.s3.central.parameters`** (consumer → central) y **`camel.uri.s3.parameters`** (producer → MinIO local); las claves compartidas siguen en **`camel.component.aws2-s3.*`**. Para otro cluster, sobreescribe esas propiedades vía `ConfigMap` / env.

Credenciales MinIO por defecto: `minio` / `minio123` (componente `aws2-s3`; alineado con los Secrets del demo).

## Rutas Camel

Definidas en `src/main/resources/camel/stream.xml` (estilo Camel K / XML DSL).

## Versiones

- **Quarkus / Camel Quarkus** (platform BOM): **3.20.6** (`io.quarkus.platform:quarkus-bom` + `quarkus-camel-bom`).
- **Java**: **21**.

Se eliminaron dependencias no usadas (`quarkus-openshift`, `camel-quarkus-servlet`) y el BOM antiguo Red Hat 3.2.6 para facilitar builds en Maven Central sin suscripción.

## Fallo en OpenShift: `Exec format error` al arrancar

Solo aplica a imágenes **nativas**: el binario no coincide con la CPU del nodo. Con imagen **JVM** (por defecto) no suele ocurrir. Si usas el tag **`:edge-manager-native`**, reconstruye con **`edge-manager-native`** (incluye **`linux/amd64`**) o pasa a **JVM**.
