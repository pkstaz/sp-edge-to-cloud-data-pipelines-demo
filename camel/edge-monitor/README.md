# Edge Monitor (Quarkus + Camel Quarkus)

Service in namespace **`edge1`** that consumes the **Kafka** topic named after the edge id (same as the namespace, e.g. **`edge1`**) and forwards messages to **MQTT** on the local AMQ Broker (**`broker-amq-mqtt-0-svc:1883`**). Same deployment pattern as **edge-manager** / **central-feeder**: JVM image on Quay with its own tag.

## Quay image (solution pattern)

Repository: **`quay.io/<org>/sp-edge-to-cloud-data-pipelines-demo`** — tag:

- **`:edge-monitor-jvm`**

Variables: **`deployment/sp-demo-images.env.sh`** (`QUAY_ORG`, `SP_QUAY_REPOSITORY`, `EDGE_MONITOR_JVM_TAG`).

## Prerequisites

- **Kafka** **Ready** in **`central`** (`my-cluster-kafka-bootstrap.central.svc:9092` from the pod — see **`application.properties`**).
- **AMQ Broker** MQTT in **`edge1`** with Service **`broker-amq-mqtt-0-svc`** (demo **`deployment/edge/amq-broker.yaml`**).
- Topic **`{edgeId}`** (e.g. **`edge1`**) must exist or be auto-created when producers publish (feeder emits to this topic).

## Configuration

Routing is in **`src/main/resources/camel/stream.xml`**. **`edge.id`** defaults to the pod namespace via **`KUBERNETES_NAMESPACE`** (set in **`deployment/edge/edge-monitor-deployment.yaml`**).

## Build JAR (JVM)

```bash
cd camel/edge-monitor
./mvnw -DskipTests package
```

## Build and push image

From repository root:

```bash
bash deployment/build-push-images.sh edge-monitor-jvm
```

Or manual (after **`source deployment/sp-demo-images.env.sh`**):

```bash
cd camel/edge-monitor
./mvnw -DskipTests package
podman build --platform linux/amd64 -f src/main/docker/Dockerfile.jvm -t "${SP_IMAGE_EDGE_MONITOR_JVM}" .
podman push "${SP_IMAGE_EDGE_MONITOR_JVM}"
```

## Deploy on OpenShift

After the image is on Quay:

```bash
oc project edge1
oc apply -f deployment/edge/edge-monitor-deployment.yaml
oc rollout status deployment/edge-monitor -n edge1 --timeout=300s
```

**Install script:** **`bash install-demo-steps.sh`** applies this manifest by default after Edge Manager (skip with **`SKIP_EDGE_MONITOR=1`**).

Shorter pointer: **`Readme.txt`**.
