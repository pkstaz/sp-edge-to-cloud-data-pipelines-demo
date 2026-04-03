#!/usr/bin/env bash
# Un solo pod en namespace central: cliente mc (binario en /tmp) + tar para oc cp.
# 1) Crea buckets estándar (salvo SKIP_MINIO_BUCKETS=1).
# 2) Sube deployment/pipeline/s3/workbench/ → bucket workbench (prefijo retrain-…/ del pipeline Tekton).
# 3) Sube dataset/images → edge1-data (salvo SKIP_MINIO_TRAINING_DATA=1 o directorio vacío).
#
# Variables: OC, CENTRAL_NS, MINIO_SYNC_POD_IMAGE, DATASET_IMAGES_DIR, MINIO_TRAINING_BUCKET,
#            PIPELINE_S3_WORKBENCH_DIR (por defecto …/deployment/pipeline/s3/workbench)
#            MINIO_TRAINING_S3_PREFIX (por defecto images — coincide con step-01/step-02)
# SKIP_MINIO_BUCKETS=1 — no crea workbench/edge1-* (sigue asegurando buckets tocados por uploads).
# SKIP_MINIO_TRAINING_DATA=1 — no sube dataset a edge1-data.
# SKIP_WORKBENCH_S3_ARTIFACTS=1 — no sube los .tar.gz de Elyra al bucket workbench.
#
set -euo pipefail

: "${OC:=oc}"
CENTRAL_NS="${CENTRAL_NS:-central}"
BUCKET="${MINIO_TRAINING_BUCKET:-edge1-data}"
# step-01.ipynb descarga a mount_path+Key; step-02 usa mount_path+"images/". Las claves S3 deben ser images/...
: "${MINIO_TRAINING_S3_PREFIX:=images}"
: "${MINIO_SYNC_POD_IMAGE:=docker.io/library/alpine:3.20}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DATASET_IMAGES_DIR="${DATASET_IMAGES_DIR:-${REPO_ROOT}/dataset/images}"
WORKBENCH_S3_LOCAL="${PIPELINE_S3_WORKBENCH_DIR:-${REPO_ROOT}/deployment/pipeline/s3/workbench}"

if [[ "${SKIP_MINIO_BUCKETS:-}" == "1" && "${SKIP_MINIO_TRAINING_DATA:-}" == "1" && "${SKIP_WORKBENCH_S3_ARTIFACTS:-}" == "1" ]]; then
  echo "Saltando MinIO: SKIP_* en buckets, dataset y artefactos workbench."
  exit 0
fi

"$OC" whoami &>/dev/null || {
  echo "Inicia sesión con oc antes de continuar." >&2
  exit 1
}

if ! "$OC" get svc minio-service -n "$CENTRAL_NS" &>/dev/null; then
  echo "No hay Service minio-service en $CENTRAL_NS. Despliega MinIO primero." >&2
  exit 1
fi

_do_dataset=false
if [[ "${SKIP_MINIO_TRAINING_DATA:-}" != "1" ]]; then
  if [[ -d "$DATASET_IMAGES_DIR" ]]; then
    _file_count=$(find "$DATASET_IMAGES_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
    if [[ -n "$_file_count" && "$_file_count" -gt 0 ]]; then
      _do_dataset=true
    else
      echo "Aviso: $DATASET_IMAGES_DIR sin ficheros; se omiten subida al bucket $BUCKET." >&2
    fi
  else
    echo "Aviso: no existe $DATASET_IMAGES_DIR; se omiten subida al bucket $BUCKET." >&2
  fi
fi

_do_workbench=false
if [[ "${SKIP_WORKBENCH_S3_ARTIFACTS:-}" != "1" ]]; then
  if [[ -d "$WORKBENCH_S3_LOCAL" ]]; then
    _wb_count=$(find "$WORKBENCH_S3_LOCAL" -type f 2>/dev/null | wc -l | tr -d ' ')
    if [[ -n "$_wb_count" && "$_wb_count" -gt 0 ]]; then
      _do_workbench=true
    else
      echo "Aviso: $WORKBENCH_S3_LOCAL sin ficheros; se omiten artefactos Elyra en bucket workbench." >&2
    fi
  else
    echo "Aviso: no existe $WORKBENCH_S3_LOCAL; el PipelineRun puede fallar con NoSuchKey (véase README)." >&2
  fi
fi

if [[ "${SKIP_MINIO_BUCKETS:-}" == "1" && "${_do_dataset}" != true && "${_do_workbench}" != true ]]; then
  echo "Nada que hacer (SKIP_MINIO_BUCKETS=1 y sin dataset ni artefactos workbench que subir)."
  exit 0
fi

POD="minio-mc-setup-${RANDOM}"
echo "Pod único $POD (imagen $MINIO_SYNC_POD_IMAGE) — buckets / workbench S3 / dataset en $CENTRAL_NS"

"$OC" run "$POD" -n "$CENTRAL_NS" --restart=Never --image="$MINIO_SYNC_POD_IMAGE" \
  --command -- sh -c 'ARCH=$(uname -m); case "$ARCH" in x86_64) MC_ARCH=amd64;; aarch64|arm64) MC_ARCH=arm64;; ppc64le) MC_ARCH=ppc64le;; s390x) MC_ARCH=s390x;; *) echo "unsupported arch: $ARCH" >&2; exit 1;; esac; wget -q -O /tmp/mc "https://dl.min.io/client/mc/release/linux-${MC_ARCH}/mc" || exit 1; chmod +x /tmp/mc; exec sleep 3600'

cleanup() {
  "$OC" delete pod "$POD" -n "$CENTRAL_NS" --wait=false &>/dev/null || true
}
trap cleanup EXIT

"$OC" wait --for=condition=Ready "pod/$POD" -n "$CENTRAL_NS" --timeout=300s

if [[ "${SKIP_MINIO_BUCKETS:-}" != "1" ]]; then
  echo "Creando buckets (workbench, edge1-data, edge1-models, edge1-ready) …"
  "$OC" exec -n "$CENTRAL_NS" "$POD" -- sh -ceu '
export HOME=/tmp MC_CONFIG_DIR=/tmp/.mc
/tmp/mc alias set m http://minio-service.central.svc:9000 minio minio123
for b in workbench edge1-data edge1-models edge1-ready; do /tmp/mc mb "m/${b}" 2>/dev/null || true; done
/tmp/mc ls m/
'
else
  echo "SKIP_MINIO_BUCKETS=1 — no se recrean los cuatro buckets estándar."
  "$OC" exec -n "$CENTRAL_NS" "$POD" -- sh -ceu '
export HOME=/tmp MC_CONFIG_DIR=/tmp/.mc
/tmp/mc alias set m http://minio-service.central.svc:9000 minio minio123
'
  if [[ "${_do_dataset}" == true || "${_do_workbench}" == true ]]; then
    "$OC" exec -n "$CENTRAL_NS" "$POD" -- sh -ceu "
export HOME=/tmp MC_CONFIG_DIR=/tmp/.mc
/tmp/mc alias set m http://minio-service.central.svc:9000 minio minio123
/tmp/mc mb m/workbench 2>/dev/null || true
/tmp/mc mb m/${BUCKET} 2>/dev/null || true
"
  fi
fi

if [[ "${_do_workbench}" == true ]]; then
  echo "Subiendo artefactos Elyra ($_wb_count ficheros) desde $WORKBENCH_S3_LOCAL → s3://workbench/"
  "$OC" cp "$WORKBENCH_S3_LOCAL/." "$CENTRAL_NS/$POD:/tmp/workbench-s3/"
  "$OC" exec -n "$CENTRAL_NS" "$POD" -- sh -ceu '
export HOME=/tmp MC_CONFIG_DIR=/tmp/.mc
/tmp/mc alias set m http://minio-service.central.svc:9000 minio minio123
/tmp/mc mb m/workbench 2>/dev/null || true
/tmp/mc cp --recursive /tmp/workbench-s3/ m/workbench/
/tmp/mc ls m/workbench/
'
fi

if [[ "${_do_dataset}" == true ]]; then
  echo "Copiando ${_file_count} archivo(s) desde $DATASET_IMAGES_DIR → s3://${BUCKET}/${MINIO_TRAINING_S3_PREFIX}/ (requisito del notebook: /data/edge1/images/)"
  "$OC" cp "$DATASET_IMAGES_DIR/." "$CENTRAL_NS/$POD:/tmp/dataset-images/"
  "$OC" exec -n "$CENTRAL_NS" "$POD" -- sh -ceu "
export HOME=/tmp MC_CONFIG_DIR=/tmp/.mc
/tmp/mc alias set m http://minio-service.central.svc:9000 minio minio123
/tmp/mc mb m/${BUCKET} 2>/dev/null || true
/tmp/mc cp --recursive /tmp/dataset-images/ m/${BUCKET}/${MINIO_TRAINING_S3_PREFIX}/
/tmp/mc ls m/${BUCKET}/
"
fi

echo "Listo (MinIO: buckets, workbench S3, dataset vía pod $POD)."
