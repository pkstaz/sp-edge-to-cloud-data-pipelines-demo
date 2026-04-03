# Central feeder (Quarkus + Camel Quarkus)

Service in namespace **`central`** that accepts a **ZIP** upload on **`/zip?edgeId=<id>`** (Camel **servlet**), unpacks **`images/**`** JPEGs into MinIO **`{edgeId}-data`**, and emits **Kafka** events (topic **`trigger`** and an edge-specific topic). Uses **`rsync`** and **`find`** inside the container (see **Dockerfile.jvm**).

Same pattern as **edge-manager** / **central-delivery**: Quarkus app, **JVM** image on Quay with its own tag.

## Quay image (solution pattern)

Repository: **`quay.io/<org>/sp-edge-to-cloud-data-pipelines-demo`** — tag:

- **`:central-feeder-jvm`**

Variables: **`deployment/sp-demo-images.env.sh`** (`QUAY_ORG`, `SP_QUAY_REPOSITORY`, `CENTRAL_FEEDER_JVM_TAG`).

## Prerequisites

- MinIO in **`central`** (`minio-service:9000` from the pod).
- Kafka **Ready** in **`central`** (`my-cluster-kafka-bootstrap:9092`).
- Bucket **`{edgeId}-data`** (e.g. **`edge1-data`**) — created by the demo MinIO scripts or manually.

## Dataset ZIP layout

From repo root (see legacy **Readme.txt**):

```bash
(cd dataset && zip -r "$OLDPWD/data.zip" images)
```

## Local development

```bash
cd camel/central-feeder
# Edit %dev MinIO/Kafka routes in src/main/resources/application.properties
./mvnw quarkus:dev
```

## Build JAR (JVM)

```bash
./mvnw -DskipTests package
```

## Build and push image

From repository root:

```bash
bash deployment/build-push-images.sh central-feeder-jvm
# SKIP_PUSH=1 … | CONTAINER_ENGINE=docker …
```

## Deploy on OpenShift

```bash
oc project central
oc apply -f deployment/central/central-feeder-deployment.yaml
```

Service name is **`feeder`** (for Skupper). The YAML sets **`skupper.io/proxy: http`** on the Service.

## Configuration

| Area | Notes |
|------|--------|
| MinIO | `camel.component.aws2-s3.*` → `http://minio-service:9000` in cluster. |
| Kafka | `camel.component.kafka.brokers=my-cluster-kafka-bootstrap:9092`. |
| Upload size | `quarkus.http.limits.max-body-size=500M`. |

## Versions

- **Quarkus / Camel Quarkus**: **3.20.6** (aligned with **central-delivery** / **edge-manager**).
- **Java**: **21**.

No **`quarkus.kubernetes.deploy`** — deploy with the YAML above.

## Container image base

**Dockerfile.jvm** uses **eclipse-temurin:21-jre-alpine** and **`apk add rsync findutils`**. A **UBI + `microdnf install`** build often fails with **HTTP 403** on Red Hat CDN when the build host cannot use the RHEL repos. To build on UBI anyway, run the build on a subscribed RHEL machine or adjust repos per Red Hat’s UBI documentation.
