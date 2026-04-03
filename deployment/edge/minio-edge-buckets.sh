#!/usr/bin/env bash
# Mismo patrón que deployment/central/minio-buckets-and-dataset.sh: pod Alpine, mc en /tmp, wget estático.
# Crea en MinIO de edge los buckets del README: production, data, valid, unclassified.
#
# Requisito: MinIO desplegado en EDGE1_NS (deployment/edge/minio.yaml) y Service minio-service.
#
# Variables: OC, EDGE1_NS, MINIO_SYNC_POD_IMAGE
# SKIP_EDGE1_MINIO_BUCKETS=1 — no crea buckets (el pod de setup no se lanza).
#
set -euo pipefail

: "${OC:=oc}"
EDGE1_NS="${EDGE1_NS:-edge1}"
: "${MINIO_SYNC_POD_IMAGE:=docker.io/library/alpine:3.20}"

if [[ "${SKIP_EDGE1_MINIO_BUCKETS:-}" == "1" ]]; then
  echo "Saltando buckets MinIO edge (SKIP_EDGE1_MINIO_BUCKETS=1)."
  exit 0
fi

"$OC" whoami &>/dev/null || {
  echo "Inicia sesión con oc antes de continuar." >&2
  exit 1
}

if ! "$OC" get svc minio-service -n "$EDGE1_NS" &>/dev/null; then
  echo "No hay Service minio-service en $EDGE1_NS. Aplica deployment/edge/minio.yaml y espera el rollout." >&2
  exit 1
fi

POD="minio-edge-mc-${RANDOM}"
echo "Pod único $POD — buckets edge en $EDGE1_NS (production, data, valid, unclassified)"

"$OC" run "$POD" -n "$EDGE1_NS" --restart=Never --image="$MINIO_SYNC_POD_IMAGE" \
  --command -- sh -c 'ARCH=$(uname -m); case "$ARCH" in x86_64) MC_ARCH=amd64;; aarch64|arm64) MC_ARCH=arm64;; ppc64le) MC_ARCH=ppc64le;; s390x) MC_ARCH=s390x;; *) echo "unsupported arch: $ARCH" >&2; exit 1;; esac; wget -q -O /tmp/mc "https://dl.min.io/client/mc/release/linux-${MC_ARCH}/mc" || exit 1; chmod +x /tmp/mc; exec sleep 3600'

cleanup() {
  "$OC" delete pod "$POD" -n "$EDGE1_NS" --wait=false &>/dev/null || true
}
trap cleanup EXIT

"$OC" wait --for=condition=Ready "pod/$POD" -n "$EDGE1_NS" --timeout=300s

"$OC" exec -n "$EDGE1_NS" "$POD" -- sh -ceu "
export HOME=/tmp MC_CONFIG_DIR=/tmp/.mc
/tmp/mc alias set edge http://minio-service.${EDGE1_NS}.svc:9000 minio minio123
for b in production data valid unclassified; do /tmp/mc mb \"edge/\${b}\" 2>/dev/null || true; done
/tmp/mc ls edge/
"

echo "Listo (buckets MinIO edge vía pod $POD)."
