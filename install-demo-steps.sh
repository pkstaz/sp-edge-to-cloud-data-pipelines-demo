#!/usr/bin/env bash
#
# install-demo-steps.sh — demo install aligned with README.md (Deployment instructions).
# Each block applies manifests or helper scripts; images are not built here (see build-push-images.sh).
#
# Usage:
#   bash install-demo-steps.sh
# Rollback (keep in sync): bash uninstall-demo-steps.sh
#
# -----------------------------------------------------------------------------
# What this script installs (in order), unless skipped via env vars below
# -----------------------------------------------------------------------------
# 1.b  Cluster checks: validate-cluster-operators.sh (OpenShift version, required operators).
# 2.1  Namespace central + MinIO (deployment/central/minio.yaml).
# 2.1b Kafka (Strimzi): deployment/central/kafka.yaml → Kafka CR my-cluster + KafkaNodePool.
# 2.2  MinIO buckets + dataset/workbench uploads (deployment/central/minio-buckets-and-dataset.sh).
# 2.3  Namespace tf (TensorFlow / RHOAI dashboard label).
# 2.4  Data connection Secret dc1 (deployment/tf/data-connection-dc1.yaml).
# 2.4b DataSciencePipelinesApplication dspa.
# 2.4c Pipeline PVC (deployment/pipeline/pvc.yaml).
# 2.4d Workbench notebook wb1 (deployment/tf/apply-notebook-wb1.sh).
# 2.4e Copy workbench/ into the notebook volume (deployment/tf/sync-workbench-sources.sh).
# 2.5  OpenShift console namespace bookmarks (optional python3 + oc patch).
# 3    Tekton Pipeline train-model + pipeline ServiceAccount/RBAC.
# 3*   Tekton Triggers: TriggerBinding, TriggerTemplate, EventListener (unless SKIP_TEKTON_TRIGGERS=1).
# 3.a Central delivery: oc apply only — deployment/central/central-delivery-deployment.yaml (image on Quay first).
# 3.a.feeder Central feeder: oc apply only — deployment/central/central-feeder-deployment.yaml; Service feeder + Skupper annotation (image on Quay first).
# 3    First PipelineRun from pipelinerun-example.yaml (unless SKIP_PIPELINE_RUN=1).
# 3.b  edge1: AMQ Broker MQTT + Route broker-amq-mqtt.
# 3.c  edge1: MinIO + edge buckets (minio-edge-buckets.sh).
# 3.d  Skupper link MinIO central ↔ edge (deployment/si/skupper-link-minio.sh).
# 3.e  Ensure edge1 exists if only Edge Manager / tf / Camel K / Edge Shopper need it.
# 4    Edge Manager — oc apply only (deployment/edge/edge-manager-deployment.yaml); image on Quay first.
# 4b   Edge Monitor — oc apply only (deployment/edge/edge-monitor-deployment.yaml); image on Quay first.
# 5    TensorFlow Serving — oc apply only (deployment/edge/tensorflow.yaml).
# 5b   edge1: Camel K price-engine — registry secret, IntegrationPlatform, ConfigMap catalogue, kamel run + wait + route
# 5c   edge1: Edge Shopper — ConfigMap catalogue (shared), deployment/edge/edge-shopper-deployment.yaml + rollout
# End  Prints Edge Shopper UI URLs (Route camel-edge) unless SKIP_EDGE_SHOPPER_URLS=1 or SKIP_EDGE_SHOPPER=1.
#      Prints copy/paste inference commands (client/infer.sh + curl) unless SKIP_TF_INFERENCE_HINT=1.
#
# README §6 “deliver model” ↔ steps 4–5 above (Edge Manager → edge MinIO production/; tf-server serves it).
# README §7 “pipeline trigger” ↔ section 3 (Tekton Triggers + optional §3.a central-delivery → EventListener).
# README §8 “data ingestion” ↔ §3.a.feeder (central-feeder Deployment + Service feeder).
#
# Not covered here (README / manual): RHDP cluster request, Quay image build/push, pipeline-template.yaml (stub only).
#
# -----------------------------------------------------------------------------
# Environment variables (skip flags and tuning)
# -----------------------------------------------------------------------------
# SKIP_CLUSTER_VALIDATION=1       — skip validate-cluster-operators.sh
# SKIP_CONSOLE_NAMESPACE_FAVORITES=1 — skip console namespace bookmarks patch
# SKIP_WORKBENCH=1                — skip workbench wb1
# SKIP_WORKBENCH_SOURCES=1       — skip rsync workbench/ into notebook PVC
# SKIP_MINIO_TRAINING_DATA=1     — skip dataset upload to edge1-data/images/…
# MINIO_TRAINING_S3_PREFIX=images — S3 prefix under edge1-data (default images)
# SKIP_WORKBENCH_S3_ARTIFACTS=1  — skip upload deployment/pipeline/s3/workbench → workbench bucket
# SKIP_MINIO_BUCKETS=1           — skip bucket creation path in minio-buckets-and-dataset.sh (see script)
# SKIP_KAFKA=1                   — skip deployment/central/kafka.yaml (AMQ Streams operator must exist)
# SKIP_TEKTON_TRIGGERS=1         — skip TriggerBinding, TriggerTemplate, EventListener
# SKIP_PIPELINE_RUN=1            — skip initial oc create pipelinerun-example.yaml
# PIPELINE_RUN_TIMEOUT=7200      — seconds to wait for first PipelineRun Succeeded (default 7200)
# SKIP_CENTRAL_DELIVERY=1        — skip deployment/central/central-delivery-deployment.yaml
# SKIP_CENTRAL_FEEDER=1          — skip deployment/central/central-feeder-deployment.yaml
# SKIP_EDGE1_AMQ=1               — skip AMQ Broker on edge1 (operator AMQ Broker 7.12 required if not skipped)
# SKIP_EDGE1_MINIO=1             — skip edge MinIO + buckets
# SKIP_EDGE1_MINIO_BUCKETS=1     — edge MinIO only: skip minio-edge-buckets.sh (MinIO already there)
# SKIP_SKUPPER_LINK=1            — skip Skupper; installer requires skupper CLI on PATH unless skipped
# SKIP_EDGE_MANAGER=1            — skip deployment/edge/edge-manager-deployment.yaml
# SKIP_EDGE_MONITOR=1            — skip deployment/edge/edge-monitor-deployment.yaml
# SKIP_TF_SERVING=1              — skip deployment/edge/tensorflow.yaml
# SKIP_EDGE1_CAMEL_K=1           — skip Camel K price-engine (secret, IntegrationPlatform, kamel run, route)
# SKIP_EDGE_SHOPPER=1            — skip deployment/edge/edge-shopper-deployment.yaml (and route camel-edge)
# SKIP_TF_INFERENCE_HINT=1       — skip the final “try inference” curl block printed at the end
# SKIP_EDGE_SHOPPER_URLS=1      — skip printing Edge Shopper https://…/index.html and …/admin.html at the end
# EDGE1_NS=edge1                 — edge namespace name
# OC=oc                          — OpenShift CLI binary
#
# Container images are NOT built here. Build/push once, e.g.:
#   bash deployment/build-push-images.sh
#   bash deployment/build-push-images.sh edge-manager-jvm
#   bash deployment/build-push-images.sh edge-monitor-jvm
#   bash deployment/build-push-images.sh edge-shopper-jvm
#   bash deployment/build-push-images.sh central-delivery-jvm
#   bash deployment/build-push-images.sh central-feeder-jvm
# Versioned edge-manager tags: bash deployment/publish-edge-manager-versioned.sh — see BACKLOG.md for native.
#
# If both SKIP_EDGE1_AMQ=1 and SKIP_EDGE1_MINIO=1, step 3.e still creates edge1 when Edge Manager,
# tf-server, or Camel K price-engine (5b) is enabled (so steps 4–5b do not fail on missing namespace).
#
set -euo pipefail

# Total elapsed time on exit (including on failure).
SECONDS=0
trap '
  ec=$?
  s=$SECONDS
  h=$((s / 3600))
  m=$(((s % 3600) / 60))
  r=$((s % 60))
  if ((h > 0)); then
    printf "\n=== install-demo-steps.sh: total time %dh %dm %ds · exit code %d ===\n" "$h" "$m" "$r" "$ec"
  elif ((m > 0)); then
    printf "\n=== install-demo-steps.sh: total time %dm %ds · exit code %d ===\n" "$m" "$r" "$ec"
  else
    printf "\n=== install-demo-steps.sh: total time %ds · exit code %d ===\n" "$s" "$ec"
  fi
  exit "$ec"
' EXIT

: "${OC:=oc}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Always defined for set -u; override with EDGE1_NS=my-ns before running.
EDGE1_NS="${EDGE1_NS:-edge1}"

echo "[install-demo-steps] Starting · EDGE1_NS=${EDGE1_NS} · OC=${OC} · $(date -u +%Y-%m-%dT%H:%MZ)"

# Installer does not install Skupper CLI; validates before 3.d unless SKIP_SKUPPER_LINK=1.
validate_skupper_cli_for_install() {
  [[ "${SKIP_SKUPPER_LINK:-}" == "1" ]] && return 0
  if ! command -v skupper >/dev/null 2>&1; then
    echo "skupper CLI not found on PATH (required for Service Interconnect in this install)." >&2
    echo "  Install or upgrade Skupper on this machine; the installer does not download it. See README: \"Update an existing Skupper CLI\"." >&2
    echo "  To skip Skupper: SKIP_SKUPPER_LINK=1 bash install-demo-steps.sh" >&2
    exit 1
  fi
  if ! skupper version >/dev/null 2>&1; then
    echo "skupper is on PATH but \"skupper version\" failed; check your installation." >&2
    exit 1
  fi
  echo "Skupper CLI:"
  skupper version
}

# Installer does not install kamel; validates before 5b unless SKIP_EDGE1_CAMEL_K=1.
validate_kamel_cli_for_install() {
  [[ "${SKIP_EDGE1_CAMEL_K:-}" == "1" ]] && return 0
  if ! command -v kamel >/dev/null 2>&1; then
    echo "kamel CLI not found on PATH (required for Camel K price-engine in this install)." >&2
    echo "  Install kamel aligned with Camel K operator 2.x, or skip: SKIP_EDGE1_CAMEL_K=1 bash install-demo-steps.sh" >&2
    exit 1
  fi
  echo "kamel version:"
  kamel version
}

# OpenShift console: bookmarks = ConfigMap user-settings-* in openshift-console-user-settings,
# key data \"console.namespace.bookmarks\" (JSON {\"ns\": true}). See console shared NamespaceDropdown.
console_patch_namespace_favorites() {
  [[ "${SKIP_CONSOLE_NAMESPACE_FAVORITES:-}" == "1" ]] && return 0
  command -v python3 >/dev/null 2>&1 || {
    echo "python3 not found: skipping console namespace bookmarks update." >&2
    return 0
  }

  local who settings_ns cm_name suffix uid existing merged patch_json
  who=$("$OC" whoami)
  settings_ns=openshift-console-user-settings

  if [[ "$who" == "kube:admin" ]]; then
    suffix=kubeadmin
  else
    uid=$("$OC" get user.user.openshift.io "$who" -o jsonpath='{.metadata.uid}' 2>/dev/null || true)
    if [[ -n "${uid:-}" ]]; then
      suffix=$uid
    else
      suffix=$(printf '%s' "$who" | python3 -c "import sys, hashlib; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())")
    fi
  fi
  cm_name="user-settings-${suffix}"

  if ! "$OC" get configmap "$cm_name" -n "$settings_ns" &>/dev/null; then
    echo "Console: ConfigMap $settings_ns/$cm_name not found (open the web console once as this user to create it; then re-run)." >&2
    return 0
  fi

  existing=$("$OC" get configmap "$cm_name" -n "$settings_ns" -o jsonpath='{.data.console\.namespace\.bookmarks}' 2>/dev/null || true)
  merged=$(EXISTING_JSON="$existing" python3 -c '
import json, os, sys
raw = os.environ.get("EXISTING_JSON") or ""
try:
    d = json.loads(raw) if raw.strip() else {}
except json.JSONDecodeError:
    d = {}
if not isinstance(d, dict):
    d = {}
for ns in sys.argv[1:]:
    if ns:
        d[ns] = True
print(json.dumps(d, separators=(",", ":")))
' "$@")
  patch_json=$(MERGED="$merged" python3 -c 'import json, os; print(json.dumps({"data": {"console.namespace.bookmarks": os.environ["MERGED"]}}))')
  if ! "$OC" patch configmap "$cm_name" -n "$settings_ns" --type merge -p "$patch_json"; then
    echo "Console: could not patch $cm_name (check permissions on $settings_ns)." >&2
    return 0
  fi
  echo "Console: namespace bookmarks updated in $cm_name (console.namespace.bookmarks)."
}

# After install: print copy/paste commands to hit TensorFlow Serving REST (:predict).
# See client/infer.sh and deployment/edge/tensorflow.yaml (model tea_model_b64).
print_tensorflow_inference_hint() {
  [[ "${SKIP_TF_INFERENCE_HINT:-}" == "1" ]] && return 0
  local green host q_green
  green="${SCRIPT_DIR}/client/green.jpg"
  echo ""
  echo "============================================================================="
  echo " TensorFlow Serving — sample inference (copy/paste into your shell)"
  echo "============================================================================="
  host=$("$OC" get route tf-server -n "$EDGE1_NS" -o jsonpath='{.spec.host}' 2>/dev/null || true)
  if [[ -n "$host" ]]; then
    echo "  Route: https://${host}  (REST :predict — model name tea_model_b64)"
  else
    echo "  No Route tf-server in namespace ${EDGE1_NS} (deploy step 5 or set EDGE1_NS)."
  fi
  echo "  Needs a saved model under edge MinIO s3://production/models (pipeline + Edge Manager or manual)."
  echo ""
  echo "  --- Option A: helper script -----------------------------------------------"
  echo "  EDGE1_NS=${EDGE1_NS} bash ${SCRIPT_DIR}/client/infer.sh"
  echo ""
  echo "  --- Option B: curl + python3 (same payload as infer.sh) -------------------"
  if [[ ! -f "$green" ]]; then
    echo "  (Missing sample image: ${green} — use Option A with IMAGE=/path/to.jpg or add green.jpg.)"
  elif command -v python3 >/dev/null 2>&1; then
    q_green=$(printf '%q' "$green")
    echo "  export GREEN_JPG=${q_green}"
    echo "  TF_ROUTE=\$(${OC} get route tf-server -n ${EDGE1_NS} -o jsonpath='{.spec.host}')"
    echo "  curl -sk -X POST -H 'content-type: application/json' \\"
    echo "    \"https://\${TF_ROUTE}/v1/models/tea_model_b64:predict\" \\"
    echo "    -d \"\$(python3 -c \"import pathlib,base64,json,os; p=pathlib.Path(os.environ['GREEN_JPG']); print(json.dumps({'instances':[{'b64':base64.b64encode(p.read_bytes()).decode()}]}))\")\""
  else
    echo "  (python3 not in PATH — use Option A.)"
  fi
  echo ""
  echo "============================================================================="
}

# Route camel-edge → Service edge-shopper (step 5c). Host from cluster (dynamic per cluster/apps domain).
print_edge_shopper_urls() {
  [[ "${SKIP_EDGE_SHOPPER_URLS:-}" == "1" ]] && return 0
  [[ "${SKIP_EDGE_SHOPPER:-}" == "1" ]] && return 0
  local host
  echo ""
  echo "============================================================================="
  echo " Edge Shopper — web UI (open in a browser)"
  echo "============================================================================="
  host=$("$OC" get route camel-edge -n "$EDGE1_NS" -o jsonpath='{.spec.host}' 2>/dev/null || true)
  if [[ -n "$host" ]]; then
    echo "  User (app):  https://${host}/index.html"
    echo "  Admin:       https://${host}/admin.html"
  else
    echo "  No Route camel-edge in namespace ${EDGE1_NS} (run step 5c or create: oc create route edge camel-edge --service=edge-shopper -n ${EDGE1_NS})."
  fi
  echo "============================================================================="
  echo ""
}

# =============================================================================
# 1. Provision a RHOAI environment
# =============================================================================
# README > Cluster > Request: Red Hat OpenShift AI 3 (RHDP)
#   https://catalog.demo.redhat.com/catalog?item=babylon-catalog-prod/published.openshift-ai-v3.prod&utm_source=webapp&utm_medium=share-link
#
# Manual: order the environment on Red Hat Demo Platform, wait for the cluster, log in to the console.
# (no required oc command in this step)

# 1.b Cluster requirements (README \"Cluster > Requirements\" ↔ validate-cluster-operators.sh).
# Run after: oc login …  If validation fails, the rest of the script is aborted.
# Skip: SKIP_CLUSTER_VALIDATION=1
if [[ "${SKIP_CLUSTER_VALIDATION:-}" != "1" ]]; then
  "$OC" whoami >/dev/null 2>&1 || {
    echo "Log in with oc before validation: oc login …" >&2
    exit 1
  }
  echo ""
  echo "============================================================================="
  echo " Step 1.b — Cluster / operator validation (running now…)"
  echo "============================================================================="
  echo "  → validate-cluster-operators.sh prints each check as it runs."
  echo "  → First API call (oc get csv -A) may take a while; dots (.) show it is waiting."
  echo "============================================================================="
  echo ""
  if ! bash "$SCRIPT_DIR/validate-cluster-operators.sh"; then
    echo "Cluster/operator validation failed; install aborted." >&2
    exit 1
  fi
  echo ""
  echo "[install-demo-steps] Validation OK — continuing with namespaces, MinIO, and the rest of the demo…"
  echo ""
else
  echo "[install-demo-steps] SKIP_CLUSTER_VALIDATION=1 — skipping validate-cluster-operators.sh"
fi

# =============================================================================
# 2. Create and prepare projects (central + tf)
# =============================================================================

echo "[install-demo-steps] Step 2 — central + tf (MinIO, Kafka, buckets, workbench, Tekton, edge…) — this can take many minutes."
echo ""

# 2.1 README — MinIO in project central (deployment/central/minio.yaml)
CENTRAL_NS=central
if ! "$OC" get namespace "$CENTRAL_NS" &>/dev/null; then
  "$OC" new-project "$CENTRAL_NS"
else
  "$OC" project "$CENTRAL_NS"
fi
"$OC" apply -n "$CENTRAL_NS" -f "$SCRIPT_DIR/deployment/central/minio.yaml"
"$OC" rollout status "deployment/minio" -n "$CENTRAL_NS" --timeout=300s

# 2.1b README — Kafka (AMQ Streams / Strimzi) in central (deployment/central/kafka.yaml)
# Requires operator installed (e.g. openshift-operators); not installed by this script. Skip: SKIP_KAFKA=1
if [[ "${SKIP_KAFKA:-}" != "1" ]]; then
  "$OC" project "$CENTRAL_NS"
  echo "Deploying Kafka (my-cluster) in ${CENTRAL_NS}..."
  "$OC" apply -f "$SCRIPT_DIR/deployment/central/kafka.yaml"
  if ! "$OC" wait kafka/my-cluster -n "$CENTRAL_NS" --for=condition=Ready --timeout=600s 2>/dev/null; then
    echo "Warning: timeout or Ready condition unavailable for kafka/my-cluster; check: oc get kafka,kafkanodepool,pods -n $CENTRAL_NS -l strimzi.io/cluster=my-cluster" >&2
  fi
else
  echo "Skipping Kafka: SKIP_KAFKA=1"
fi

# 2.2 README — S3 buckets + pipeline workbench artifacts (s3/workbench → workbench) + dataset/images → edge1-data.
# Single Alpine pod (mc in /tmp + tar for oc cp). See deployment/central/minio-buckets-and-dataset.sh
# Skip parts: SKIP_MINIO_BUCKETS=1 | SKIP_MINIO_TRAINING_DATA=1 | SKIP_WORKBENCH_S3_ARTIFACTS=1
# Local alternative without cluster pod: deployment/central/create-minio-buckets.sh + port-forward
if [[ "${SKIP_MINIO_BUCKETS:-}" != "1" || "${SKIP_MINIO_TRAINING_DATA:-}" != "1" || "${SKIP_WORKBENCH_S3_ARTIFACTS:-}" != "1" ]]; then
  bash "$SCRIPT_DIR/deployment/central/minio-buckets-and-dataset.sh"
fi

# 2.3 README — Data Science project: dashboard requires label opendatahub.io/dashboard=true
# (odh-dashboard DSG_CREATION). If disableKueue=false on OdhDashboardConfig, also add kueue.openshift.io/managed=true
TF_NS=tf
if ! "$OC" get namespace "$TF_NS" &>/dev/null; then
  "$OC" new-project "$TF_NS" --display-name="TensorFlow"
else
  "$OC" project "$TF_NS"
fi
"$OC" label namespace "$TF_NS" opendatahub.io/dashboard=true --overwrite

# 2.4 README — Data connection dc1 (Secret S3 → MinIO; RHOAI 3.x connections API)
"$OC" apply -f "$SCRIPT_DIR/deployment/tf/data-connection-dc1.yaml"

# 2.4b README — Pipeline server: DataSciencePipelinesApplication (RHOAI 3.x / KFP v2), no UI
"$OC" apply -f "$SCRIPT_DIR/deployment/tf/datasciencepipelinesapplication.yaml"
if ! "$OC" wait datasciencepipelinesapplication/dspa -n "$TF_NS" --for=condition=Ready --timeout=600s 2>/dev/null; then
  echo "Warning: DSPA Ready timeout or condition missing; check: oc get dspa,pods -n $TF_NS" >&2
fi

# 2.4c README — Shared PVC for Tekton pipeline tasks (Elyra / train-model)
"$OC" apply -f "$SCRIPT_DIR/deployment/pipeline/pvc.yaml"

# 2.4d README — Workbench wb1 (Notebook + PVC; default TF CUDA Py3.12 image; WORKBENCH_ACCEL=rocm if no CUDA)
# Skip: SKIP_WORKBENCH=1. See deployment/tf/apply-notebook-wb1.sh (NOTEBOOK_IS_NS, WORKBENCH_ISTAG, WORKBENCH_IMAGE).
if [[ "${SKIP_WORKBENCH:-}" != "1" ]]; then
  bash "$SCRIPT_DIR/deployment/tf/apply-notebook-wb1.sh"
fi

# 2.4e README — Copy workbench/ into the Jupyter volume (no manual UI upload)
# Skip: SKIP_WORKBENCH_SOURCES=1 (or SKIP_WORKBENCH=1). See deployment/tf/sync-workbench-sources.sh
if [[ "${SKIP_WORKBENCH:-}" != "1" ]] && [[ "${SKIP_WORKBENCH_SOURCES:-}" != "1" ]]; then
  bash "$SCRIPT_DIR/deployment/tf/sync-workbench-sources.sh"
fi

# 2.5 OpenShift console project/namespace dropdown bookmarks (same user as oc).
console_patch_namespace_favorites "$CENTRAL_NS" "$TF_NS" "$EDGE1_NS"

# =============================================================================
# 3. Tekton pipeline (train-model) + optional first run + triggers
# =============================================================================
# Manifests under deployment/pipeline/ — apply pipeline + optional triggers + optional first PipelineRun.
# Skip triggers: SKIP_TEKTON_TRIGGERS=1 | Skip first run: SKIP_PIPELINE_RUN=1
#
PIPELINE_DIR="$SCRIPT_DIR/deployment/pipeline"
: "${PIPELINE_RUN_TIMEOUT:=7200}"
# PVC applied in 2.4c; if you run a partial install, apply pvc.yaml before the pipeline.
"$OC" apply -f "$PIPELINE_DIR/pipeline.yaml"
"$OC" apply -f "$PIPELINE_DIR/rbac-pipeline-sa.yaml"
if [[ "${SKIP_TEKTON_TRIGGERS:-}" != "1" ]]; then
  "$OC" apply -f "$PIPELINE_DIR/trigger-binding.yaml"
  "$OC" apply -f "$PIPELINE_DIR/trigger-template.yaml"
  "$OC" apply -f "$PIPELINE_DIR/event-listener.yaml"
fi

# =============================================================================
# 3.a Central delivery (Camel Quarkus) — deployment/central/central-delivery-deployment.yaml
# =============================================================================
# Only oc apply + rollout; no Maven/image build. Image: Quay tag central-delivery-jvm.
# Needs Kafka in $CENTRAL_NS (step 2.1b unless SKIP_KAFKA=1) and EventListener in tf when using full flow.
# Skip: SKIP_CENTRAL_DELIVERY=1
if [[ "${SKIP_CENTRAL_DELIVERY:-}" != "1" ]]; then
  "$OC" project "$CENTRAL_NS"
  echo "Deploying central-delivery in ${CENTRAL_NS}..."
  "$OC" apply -f "$SCRIPT_DIR/deployment/central/central-delivery-deployment.yaml"
  "$OC" rollout status deployment/central-delivery -n "$CENTRAL_NS" --timeout=300s
else
  echo "Skipping central-delivery: SKIP_CENTRAL_DELIVERY=1"
fi

# =============================================================================
# 3.a.feeder Central feeder (Camel Quarkus) — deployment/central/central-feeder-deployment.yaml
# =============================================================================
# Only oc apply + rollout; no Maven/container build (use deployment/build-push-images.sh beforehand).
# HTTP servlet:/zip ingest; Service name feeder (Skupper skupper.io/proxy on Service).
# Needs MinIO + Kafka in central. Quay tag central-feeder-jvm. Skip: SKIP_CENTRAL_FEEDER=1
if [[ "${SKIP_CENTRAL_FEEDER:-}" != "1" ]]; then
  "$OC" project "$CENTRAL_NS"
  echo "Deploying central-feeder in ${CENTRAL_NS} (Service feeder)..."
  "$OC" apply -f "$SCRIPT_DIR/deployment/central/central-feeder-deployment.yaml"
  "$OC" rollout status deployment/central-feeder -n "$CENTRAL_NS" --timeout=300s
else
  echo "Skipping central-feeder: SKIP_CENTRAL_FEEDER=1"
fi

if [[ "${SKIP_PIPELINE_RUN:-}" != "1" ]]; then
  echo "Creating initial PipelineRun (train-model) in $TF_NS (pipelinerun-example.yaml)..."
  PR_NAME=$("$OC" create -f "$PIPELINE_DIR/pipelinerun-example.yaml" -o jsonpath='{.metadata.name}')
  echo "PipelineRun: $PR_NAME — waiting for Succeeded (timeout ${PIPELINE_RUN_TIMEOUT}s)..."
  if "$OC" wait --for=condition=Succeeded "pipelinerun/${PR_NAME}" -n "$TF_NS" --timeout="${PIPELINE_RUN_TIMEOUT}s"; then
    echo "PipelineRun ${PR_NAME} completed successfully."
  else
    echo "Warning: PipelineRun ${PR_NAME} did not report Succeeded within ${PIPELINE_RUN_TIMEOUT}s or failed. Check: oc get pipelinerun -n $TF_NS; oc describe pipelinerun/${PR_NAME} -n $TF_NS" >&2
  fi
else
  echo "Skipping initial pipeline run: SKIP_PIPELINE_RUN=1 (create manually: oc create -f deployment/pipeline/pipelinerun-example.yaml)"
fi

# =============================================================================
# 3.b edge1 — AMQ Broker (MQTT) + Route broker-amq-mqtt
# =============================================================================
# README > Prepare the Edge1 environment — operator from OperatorHub (cluster-wide or namespace).
# Skip if no operator: SKIP_EDGE1_AMQ=1
if [[ "${SKIP_EDGE1_AMQ:-}" != "1" ]]; then
  if ! "$OC" get namespace "$EDGE1_NS" &>/dev/null; then
    "$OC" new-project "$EDGE1_NS"
  else
    "$OC" project "$EDGE1_NS"
  fi
  "$OC" apply -n "$EDGE1_NS" -f "$SCRIPT_DIR/deployment/edge/amq-broker.yaml"
  echo "Waiting for StatefulSet broker-amq-ss (AMQ Broker operator must reconcile the CR)..."
  deadline=$((SECONDS + 300))
  while ! "$OC" get statefulset broker-amq-ss -n "$EDGE1_NS" &>/dev/null; do
    if (( SECONDS > deadline )); then
      echo "Timeout: broker-amq-ss not found in $EDGE1_NS. Is AMQ Broker operator 7.12 installed? oc get activemqartemis -n $EDGE1_NS" >&2
      exit 1
    fi
    sleep 5
  done
  "$OC" rollout status statefulset/broker-amq-ss -n "$EDGE1_NS" --timeout=300s
  if ! "$OC" get route broker-amq-mqtt -n "$EDGE1_NS" &>/dev/null; then
    "$OC" create route edge broker-amq-mqtt --service broker-amq-mqtt-0-svc -n "$EDGE1_NS"
  else
    echo "Route broker-amq-mqtt already exists in $EDGE1_NS; not recreated."
  fi
fi

# =============================================================================
# 3.c edge1 — MinIO (same pattern as central) + buckets production/data/valid/unclassified
# =============================================================================
# deployment/edge/minio.yaml + deployment/edge/minio-edge-buckets.sh
# Skip: SKIP_EDGE1_MINIO=1 | SKIP_EDGE1_MINIO_BUCKETS=1 (buckets only)
if [[ "${SKIP_EDGE1_MINIO:-}" != "1" ]]; then
  if ! "$OC" get namespace "$EDGE1_NS" &>/dev/null; then
    "$OC" new-project "$EDGE1_NS"
  else
    "$OC" project "$EDGE1_NS"
  fi
  "$OC" apply -n "$EDGE1_NS" -f "$SCRIPT_DIR/deployment/edge/minio.yaml"
  "$OC" rollout status deployment/minio -n "$EDGE1_NS" --timeout=300s
  EDGE1_NS="${EDGE1_NS:-edge1}" bash "$SCRIPT_DIR/deployment/edge/minio-edge-buckets.sh"
fi

# =============================================================================
# 3.d Service Interconnect (Skupper) — expose MinIO central to the edge network
# =============================================================================
# deployment/si/skupper-link-minio.sh — default. Skip: SKIP_SKUPPER_LINK=1
if [[ "${SKIP_SKUPPER_LINK:-}" == "1" ]]; then
  echo "Skipping Service Interconnect (Skupper): SKIP_SKUPPER_LINK=1"
else
  validate_skupper_cli_for_install
  bash "$SCRIPT_DIR/deployment/si/skupper-link-minio.sh"
fi

# =============================================================================
# 3.e Ensure edge1 project exists (for Edge Manager and/or tf-server)
# =============================================================================
# 3.b creates edge1 only if AMQ is not skipped; 3.c only if edge MinIO is not skipped. If both are skipped,
# edge1 might be missing and steps 4–5 used to fail. Create it here when needed.
# Re-affirm EDGE1_NS for set -u / odd environments.
EDGE1_NS="${EDGE1_NS:-edge1}"
if [[ "${SKIP_EDGE_MANAGER:-}" != "1" ]] || [[ "${SKIP_EDGE_MONITOR:-}" != "1" ]] || [[ "${SKIP_TF_SERVING:-}" != "1" ]] || [[ "${SKIP_EDGE1_CAMEL_K:-}" != "1" ]] || [[ "${SKIP_EDGE_SHOPPER:-}" != "1" ]]; then
  if ! "$OC" get namespace "$EDGE1_NS" &>/dev/null; then
    echo "Creating project ${EDGE1_NS} (required for Edge Manager, Edge Monitor, TensorFlow, Camel K price-engine, and/or Edge Shopper; not created in 3.b/3.c)..."
    "$OC" new-project "$EDGE1_NS"
  fi
fi

# =============================================================================
# 4. Edge Manager (Camel Quarkus) — deployment/edge/edge-manager-deployment.yaml
# =============================================================================
# Requires image on Quay (e.g. :edge-manager-jvm) and edge1 project. Skip: SKIP_EDGE_MANAGER=1
if [[ "${SKIP_EDGE_MANAGER:-}" != "1" ]]; then
  "$OC" project "$EDGE1_NS"
  echo "Deploying Edge Manager in ${EDGE1_NS}..."
  "$OC" apply -f "$SCRIPT_DIR/deployment/edge/edge-manager-deployment.yaml"
  "$OC" rollout status deployment/edge-manager -n "$EDGE1_NS" --timeout=300s
else
  echo "Skipping Edge Manager: SKIP_EDGE_MANAGER=1"
fi

# =============================================================================
# 4b. Edge Monitor (Camel Quarkus) — deployment/edge/edge-monitor-deployment.yaml
# =============================================================================
# Kafka in central + AMQ MQTT on edge. Quay tag edge-monitor-jvm. Skip: SKIP_EDGE_MONITOR=1
if [[ "${SKIP_EDGE_MONITOR:-}" != "1" ]]; then
  "$OC" project "$EDGE1_NS"
  echo "Deploying Edge Monitor in ${EDGE1_NS}..."
  "$OC" apply -f "$SCRIPT_DIR/deployment/edge/edge-monitor-deployment.yaml"
  "$OC" rollout status deployment/edge-monitor -n "$EDGE1_NS" --timeout=300s
else
  echo "Skipping Edge Monitor: SKIP_EDGE_MONITOR=1"
fi

# =============================================================================
# 5. TensorFlow Serving on edge1 — deployment/edge/tensorflow.yaml
# =============================================================================
# Loads model from s3://production/… (edge MinIO). Skip: SKIP_TF_SERVING=1
# Topology labels: app.kubernetes.io/name=python + app.openshift.io/runtime=tensorflow (Python icon in console; see YAML comments).
if [[ "${SKIP_TF_SERVING:-}" != "1" ]]; then
  "$OC" project "$EDGE1_NS"
  echo "Deploying TensorFlow Serving (tf-server) in ${EDGE1_NS}..."
  "$OC" apply -f "$SCRIPT_DIR/deployment/edge/tensorflow.yaml"
  "$OC" rollout status deployment/tf-server -n "$EDGE1_NS" --timeout=600s
else
  echo "Skipping TensorFlow Serving: SKIP_TF_SERVING=1"
fi

# =============================================================================
# 5b. Camel K price-engine — registry secret, IntegrationPlatform, ConfigMap, kamel run + route
# =============================================================================
# Camel K operator (community 2.x) must be installed; kamel CLI on PATH. Skip: SKIP_EDGE1_CAMEL_K=1
apply_camel_k_integration_platform() {
  local tmp
  tmp=$(mktemp)
  sed -e "s/^  namespace: edge1\$/  namespace: ${EDGE1_NS}/" \
      -e "s/^      organization: edge1\$/      organization: ${EDGE1_NS}/" \
      "$SCRIPT_DIR/deployment/edge/integration-platform-camel-k.yaml" >"$tmp"
  "$OC" apply -f "$tmp"
  rm -f "$tmp"
}

# Shared by Camel K price-engine and Edge Shopper (catalogue.json includes optional "trainable" per item).
ensure_edge1_catalogue_configmap() {
  "$OC" create configmap catalogue \
    --from-file="$SCRIPT_DIR/camel/edge-shopper/camel-price/catalogue.json" -n "$EDGE1_NS" \
    --dry-run=client -o yaml | "$OC" apply -f -
}

if [[ "${SKIP_EDGE1_CAMEL_K:-}" != "1" ]]; then
  validate_kamel_cli_for_install
  if ! "$OC" get crd integrationplatforms.camel.apache.org &>/dev/null; then
    echo "CRD integrationplatforms.camel.apache.org not found. Install Camel K operator or set SKIP_EDGE1_CAMEL_K=1." >&2
    exit 1
  fi
  "$OC" project "$EDGE1_NS"
  echo "Deploying Camel K price-engine in ${EDGE1_NS}..."
  "$OC" create secret docker-registry camel-k-registry -n "$EDGE1_NS" \
    --docker-server=image-registry.openshift-image-registry.svc:5000 \
    --docker-username=unused \
    --docker-password="$("$OC" whoami -t)" \
    --dry-run=client -o yaml | "$OC" apply -f -
  apply_camel_k_integration_platform
  ensure_edge1_catalogue_configmap
  kamel run "$SCRIPT_DIR/camel/edge-shopper/camel-price/price-engine.xml" -n "$EDGE1_NS" --name price-engine \
    --resource configmap:catalogue@/deployments/config \
    --dependency=camel:jackson --dependency=camel:jq
  echo "Waiting for integration price-engine (build can take several minutes)..."
  "$OC" wait --for=condition=Ready "integration/price-engine" -n "$EDGE1_NS" --timeout=600s
  if ! "$OC" get route price-engine -n "$EDGE1_NS" &>/dev/null; then
    "$OC" expose svc price-engine -n "$EDGE1_NS"
  else
    echo "Route price-engine already exists in ${EDGE1_NS}; not recreated."
  fi
else
  echo "Skipping Camel K price-engine: SKIP_EDGE1_CAMEL_K=1"
fi

# =============================================================================
# 5c. Edge Shopper (Camel Quarkus) — deployment/edge/edge-shopper-deployment.yaml
# =============================================================================
# Needs ConfigMap catalogue (same file as price-engine). Quay tag edge-shopper-jvm. Skip: SKIP_EDGE_SHOPPER=1
if [[ "${SKIP_EDGE_SHOPPER:-}" != "1" ]]; then
  "$OC" project "$EDGE1_NS"
  ensure_edge1_catalogue_configmap
  echo "Deploying Edge Shopper in ${EDGE1_NS}..."
  "$OC" apply -f "$SCRIPT_DIR/deployment/edge/edge-shopper-deployment.yaml"
  "$OC" rollout status deployment/edge-shopper -n "$EDGE1_NS" --timeout=300s
  if ! "$OC" get route camel-edge -n "$EDGE1_NS" &>/dev/null; then
    "$OC" create route edge camel-edge --service=edge-shopper -n "$EDGE1_NS"
  else
    echo "Route camel-edge already exists in ${EDGE1_NS}; not recreated."
  fi
else
  echo "Skipping Edge Shopper: SKIP_EDGE_SHOPPER=1"
fi

# =============================================================================
# 6. Deliver the AI/ML model (README section — implemented by steps 4–5c, no separate apply here)
# =============================================================================
# Edge Manager copies trained artifacts from central MinIO (*-ready) to edge MinIO bucket production/.
# TensorFlow Serving (tf-server) loads the model from s3://production/… on the edge.
# Edge Shopper (5c) + Camel K price-engine (5b) share ConfigMap catalogue — no extra step here.
# Nothing extra to run in this block; use SKIP_EDGE_MANAGER=1 / SKIP_EDGE_MONITOR=1 / SKIP_TF_SERVING=1 / SKIP_EDGE1_CAMEL_K=1 / SKIP_EDGE_SHOPPER=1 if you omit that path.

# =============================================================================
# 7. Create a trigger for the Pipeline (README section — implemented in section 3 above)
# =============================================================================
# Tekton TriggerBinding, TriggerTemplate, and EventListener are applied with the pipeline (unless
# SKIP_TEKTON_TRIGGERS=1). Optional: central-delivery (§3.a) forwards Kafka events to that listener.


# =============================================================================
# 8. Deploy the data ingestion system (README section — implemented in §3.a.feeder above)
# =============================================================================
# Central feeder ZIP → MinIO + Kafka: deployment/central/central-feeder-deployment.yaml (unless SKIP_CENTRAL_FEEDER=1).

# =============================================================================
# 9. Test the end to end solution — Edge Shopper URLs + inference hint
# =============================================================================

print_edge_shopper_urls
print_tensorflow_inference_hint
