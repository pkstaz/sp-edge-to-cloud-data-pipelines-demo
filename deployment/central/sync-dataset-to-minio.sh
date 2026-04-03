#!/usr/bin/env bash
# Sube solo el dataset a edge1-data usando el mismo flujo que install (un pod Alpine + mc en /tmp).
# Asume MinIO y buckets; no vuelve a crear workbench/edge1-* salvo edge1-data si falta.
#
# Variables: mismas que minio-buckets-and-dataset.sh (OC, CENTRAL_NS, DATASET_IMAGES_DIR, …)
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SKIP_MINIO_BUCKETS=1
export SKIP_WORKBENCH_S3_ARTIFACTS=1
exec bash "$SCRIPT_DIR/minio-buckets-and-dataset.sh"
