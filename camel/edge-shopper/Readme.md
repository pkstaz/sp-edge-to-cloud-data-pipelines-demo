# Edge Shopper (Quarkus + Camel Quarkus)

Browser-facing **edge** app: image **detection** (TensorFlow Serving), **ingestion** / training uploads, optional **ZIP → central feeder**, **MQTT** events, **S3** (MinIO) image storage. Same delivery pattern as **edge-manager** and **edge-monitor**: JVM container on Quay, OpenShift **`Deployment` + `Service`**, no embedded operator logic in this module.

**Platform baseline:** RHOAI / OpenShift AI **3.3**-class demos and **OpenShift 4** with the operators and versions described in the **repository root `README.md`** (AMQ Broker **7.12**, Strimzi Kafka, MinIO, Skupper, Camel K **2.x** for **price-engine** only, etc.).

---

## Quay image

Repository: **`quay.io/<org>/sp-edge-to-cloud-data-pipelines-demo`** — tag:

- **`:edge-shopper-jvm`**

Variables: **`deployment/sp-demo-images.env.sh`** (`QUAY_ORG`, `SP_QUAY_REPOSITORY`, `EDGE_SHOPPER_JVM_TAG`).

Build / push from **repository root**:

```bash
bash deployment/build-push-images.sh edge-shopper-jvm
# SKIP_PUSH=1 … | CONTAINER_ENGINE=docker …
```

Runtime image uses **UBI 9 + OpenJDK 21** (`src/main/docker/Dockerfile.jvm`), aligned with **edge-manager** / **edge-monitor**.

---

## Prerequisites (cluster)

Typical **`edge1`** stack for this demo (details and versions in root **`README.md`**):

| Dependency | Role |
| ---------- | ---- |
| **TensorFlow Serving** (`tf-server`) | `POST /v1/models/tea_model_b64:predict` |
| **Camel K `price-engine`** | HTTP `/price`, `/item`; reads **`catalogue.json`** |
| **AMQ Broker** (MQTT) | Service **`broker-amq-mqtt-0-svc`**, route **`broker-amq-mqtt`** |
| **MinIO** on edge | `minio-service:9000`, buckets e.g. **data** / **valid** / **unclassified** |
| **Central feeder** (Skupper / `feeder`) | ZIP upload path used by **`/zip`** when configured |
| **ConfigMap `catalogue`** | Shared with **price-engine**; mounted at **`/deployments/config`** |

---

## Camel K price-engine (catalogue)

The **price** API is **not** this Quarkus app; it is **`camel/edge-shopper/camel-price/price-engine.xml`** deployed with **Camel K**. **`catalogue.json`** must exist as ConfigMap **`catalogue`** (key **`catalogue.json`**).

From **repository root** (paths are relative to root):

```bash
oc project edge1
oc create configmap catalogue \
  --from-file=camel/edge-shopper/camel-price/catalogue.json -n edge1 \
  --dry-run=client -o yaml | oc apply -f -
kamel run camel/edge-shopper/camel-price/price-engine.xml -n edge1 --name price-engine \
  --resource configmap:catalogue@/deployments/config \
  --dependency=camel:jackson --dependency=camel:jq
oc wait --for=condition=Ready integration/price-engine -n edge1 --timeout=600s
oc expose svc price-engine -n edge1
```

**IntegrationPlatform** / registry secret on OpenShift: see **`deployment/edge/integration-platform-camel-k.yaml`** and root **README**.

Local JBang (optional):

```bash
cd camel/edge-shopper/camel-price
camel run * --port 8090
```

Smoke test (replace host with your route):

```bash
HOST=$(oc get route price-engine -n edge1 -o jsonpath='{.spec.host}')
curl -sk -H "item: tea-green" "https://${HOST}/price"
```

---

## Deploy Edge Shopper on OpenShift

Manifest: **`deployment/edge/edge-shopper-deployment.yaml`** — **`Deployment` / `Service` `edge-shopper`**, port **8080**, volume **ConfigMap `catalogue`** → **`/deployments/config`**.

From **repository root**:

```bash
oc project edge1
oc create configmap catalogue \
  --from-file=camel/edge-shopper/camel-price/catalogue.json -n edge1 \
  --dry-run=client -o yaml | oc apply -f -
oc apply -f deployment/edge/edge-shopper-deployment.yaml
oc rollout status deployment/edge-shopper -n edge1 --timeout=300s
oc create route edge camel-edge --service=edge-shopper -n edge1
```

**Automated demo install:** from root, **`bash install-demo-steps.sh`** applies the same (step **5c**, after Camel K **5b**). **`SKIP_EDGE_SHOPPER=1`** skips this app.

**End of install script:** URLs are printed from **`oc get route camel-edge`** ( **`…/index.html`** and **`…/admin.html`** ). **`SKIP_EDGE_SHOPPER_URLS=1`** suppresses that block.

---

## Product catalogue (`catalogue.json`)

- **Single source in Git:** **`camel/edge-shopper/camel-price/catalogue.json`**
- **Fields:** **`item`**, **`label`**, **`price`**, optional **`trainable`** (`true` | `false`)
- **Price-engine:** uses **`item` / `label` / `price`** (ignores **`trainable`**)
- **Shopper ingestion options:** only entries with **`"trainable": true`** appear in the training label list; those **`item`** values must still exist in the catalogue for **`/item`** and **`/price`**

Updating **only** the ConfigMap (no image rebuild): re-apply the ConfigMap, then restart **edge-shopper** and **price-engine** (or delete the Camel K pod). Full procedure: root **README**, *Updating the product catalogue (ConfigMap only)*.

---

## Configuration

**`src/main/resources/application.properties`**: MQTT URIs, **`endpoint.detections.host`** (tf-server), **`endpoint.price.host`** (`price-engine`), S3/MinIO, **`camel.uri.feeder`**, dev overrides (`%dev.…`). **`camel.uri.config.training`** points to **`file:/deployments/config/catalogue.json`** in cluster and **`classpath:local-training-options.json`** in dev — keep **`local-training-options.json`** in sync with **`catalogue.json`** shape when you change flags.

---

## Local development

```bash
cd camel/edge-shopper
./mvnw quarkus:dev
```

Adjust **`%dev.***` properties for your routes (TensorFlow, price stub, MinIO, MQTT).

---

## Test with curl (local)

**Binary**

```bash
MY_IMAGE=./path/to/image.jpg
MY_ROUTE=http://localhost:8080
curl -H 'Content-Type:application/octet-stream' "${MY_ROUTE}/binary" --data-binary @"${MY_IMAGE}"
```

**JSON (base64 body)**

```bash
MY_IMAGE=./path/to/image.jpg
MY_ROUTE=http://localhost:8080
if B64=$(base64 -w0 "$MY_IMAGE" 2>/dev/null); then :; else B64=$(base64 -i "$MY_IMAGE" 2>/dev/null | tr -d '\n'); fi
curl -sS -X POST -H "Content-Type: application/json" "${MY_ROUTE}/detection" \
  -d "{\"image\":\"${B64}\"}"
```

---

## OpenShift UI URLs

After **`Route camel-edge`** exists:

```bash
HOST=$(oc get route camel-edge -n edge1 -o jsonpath='{.spec.host}')
echo "https://${HOST}/index.html"
echo "https://${HOST}/admin.html"
```

Use **`EDGE1_NS`** if your namespace is not **`edge1`**.

---

## Alternative: Quarkus Kubernetes deploy

```bash
./mvnw clean package -DskipTests -Dquarkus.kubernetes.deploy=true
```

The supported path for this demo is **YAML + Quay + ConfigMap `catalogue`** so mounts match **price-engine**.

---

## Publishing to the solution-pattern fork (maintainers)

Upstream solution-pattern work may live in a **fork** (e.g. **`sp-edge-to-cloud-data-pipelines-demo`**) while the parent repo is unchanged. Example: create a branch for **RHOAI 3.3**-aligned work and push only there:

```bash
# once: add the fork (use another name if this remote already exists)
git remote add demo git@github.com:pkstaz/sp-edge-to-cloud-data-pipelines-demo.git

git fetch demo 2>/dev/null || true
git checkout -b rhoai-3.3
# commit your changes, then:
git push -u demo rhoai-3.3
```

Use **`git remote -v`** to avoid duplicating remotes; rename **`demo`** if you prefer (**`bruno`**, **`fork`**, etc.). Do **not** push **`rhoai-3.3`** to **`origin`** until you intend to.
