#!/usr/bin/env bash
# Crea los buckets del README en MinIO usando la API S3 (cliente mc de MinIO).
# install-demo-steps.sh ya los crea con un pod in-cluster; usa este script si
# prefieres mc en tu máquina (p. ej. port-forward).
#
# Requisito: https://min.io/docs/minio/linux/reference/minio-mc.html — instalar `mc`.
#
# Desde tu máquina (el Service solo es accesible dentro del cluster):
#   oc port-forward -n central svc/minio-service 9000:9000
#   MINIO_ENDPOINT=http://127.0.0.1:9000 bash deployment/central/create-minio-buckets.sh
#
# Desde un pod en el mismo namespace (sin port-forward):
#   MINIO_ENDPOINT=http://minio-service.central.svc:9000 bash deployment/central/create-minio-buckets.sh
#
# Con la Route HTTPS del API (host desde: oc get route minio-api -n central -o jsonpath='{.spec.host}'):
#   MINIO_ENDPOINT=https://minio-api-central....apps.... bash deployment/central/create-minio-buckets.sh
#
set -euo pipefail

: "${MINIO_ENDPOINT:=http://127.0.0.1:9000}"
: "${MINIO_ROOT_USER:=minio}"
: "${MINIO_ROOT_PASSWORD:=minio123}"

ALIAS=demo-rhods
mc alias set "$ALIAS" "$MINIO_ENDPOINT" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null

BUCKETS=(workbench edge1-data edge1-models edge1-ready)

for b in "${BUCKETS[@]}"; do
  # Idempotente: si el bucket ya existe, mc mb falla y seguimos.
  mc mb "${ALIAS}/${b}" 2>/dev/null || true
  echo "bucket: ${b}"
done

echo "Listo. Comprueba con: mc ls ${ALIAS}/"
