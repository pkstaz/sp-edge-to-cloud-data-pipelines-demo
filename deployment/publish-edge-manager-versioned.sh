#!/usr/bin/env bash
# Homologación: build/push principal en quay.io/$QUAY_ORG/$REPO:edge-manager-jvm (lo que usa el Deployment).
# Opcionalmente también publica :edge-manager-jvm-$N (mismo digest) para historial en Quay; N va en
# deployment/edge/edge-manager-image.version.
#
# Uso:
#   bash deployment/publish-edge-manager-versioned.sh
#   SKIP_EXTRA_TAG=1 bash deployment/publish-edge-manager-versioned.sh   # solo :edge-manager-jvm
#   SKIP_ROLLOUT=1 bash deployment/publish-edge-manager-versioned.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=sp-demo-images.env.sh
source "${SCRIPT_DIR}/sp-demo-images.env.sh"

: "${EDGE1_NS:=edge1}"
VERSION_FILE="${SCRIPT_DIR}/edge/edge-manager-image.version"
DEPLOY_YAML="${SCRIPT_DIR}/edge/edge-manager-deployment.yaml"

LAST="$(cat "${VERSION_FILE}" 2>/dev/null || echo 0)"
if ! [[ "${LAST}" =~ ^[0-9]+$ ]]; then
  echo "Contenido inválido en ${VERSION_FILE}: '${LAST}' (esperado entero). Corrige o borra el archivo." >&2
  exit 1
fi
N=$((LAST + 1))
echo "${N}" > "${VERSION_FILE}"

# Tag homologado (YAML / install-demo)
export EDGE_MANAGER_JVM_TAG="edge-manager-jvm"
export SP_IMAGE_EDGE_MANAGER_JVM="${SP_QUAY_IMAGE}:${EDGE_MANAGER_JVM_TAG}"
echo "=== edge-manager (homologado) → ${SP_IMAGE_EDGE_MANAGER_JVM} | correlativo Quay N=${N} ==="

SKIP_PUSH="${SKIP_PUSH:-}" bash "${SCRIPT_DIR}/build-push-images.sh" edge-manager-jvm

if [[ "${SKIP_PUSH:-}" != "1" && "${SKIP_EXTRA_TAG:-}" != "1" ]]; then
  VERS_IMAGE="${SP_QUAY_IMAGE}:edge-manager-jvm-${N}"
  echo "=== tag adicional (mismo digest): ${VERS_IMAGE} ==="
  "${CONTAINER_ENGINE}" tag "${SP_IMAGE_EDGE_MANAGER_JVM}" "${VERS_IMAGE}"
  "${CONTAINER_ENGINE}" push "${VERS_IMAGE}"
fi

# YAML siempre apunta al tag homologado
IMAGE="${SP_QUAY_IMAGE}:edge-manager-jvm" perl -i -pe \
  's#image: quay.io/[^ ]+/sp-edge-to-cloud-data-pipelines-demo:edge-manager-jvm\S*#image: $ENV{IMAGE}#' \
  "${DEPLOY_YAML}"

if [[ "${SKIP_ROLLOUT:-}" == "1" ]]; then
  echo "SKIP_ROLLOUT=1 — no se aplica OpenShift. Imagen: ${SP_IMAGE_EDGE_MANAGER_JVM}"
  exit 0
fi

oc apply -f "${DEPLOY_YAML}"
oc rollout status "deployment/edge-manager" -n "${EDGE1_NS}" --timeout=300s
POD="$(oc get pods -n "${EDGE1_NS}" -l app=edge-manager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [[ -n "${POD}" ]]; then
  echo "=== logs ${POD} (tail 120) ==="
  oc logs -n "${EDGE1_NS}" "${POD}" --tail=120 2>&1 || true
else
  echo "No se encontró pod edge-manager en ${EDGE1_NS}" >&2
fi
