#!/usr/bin/env bash
# Construye y (opcionalmente) publica en Quay las imágenes del demo.
# Ejecútalo cuando cambie el código; el instalador (install-demo-steps.sh) solo aplica YAML
# y reutiliza las imágenes ya publicadas.
#
# Uso (desde la raíz del repo):
#   bash deployment/build-push-images.sh                    # default: edge-manager + edge-monitor + edge-shopper + central-delivery + central-feeder (JVM)
#   bash deployment/build-push-images.sh edge-manager-jvm
#   bash deployment/build-push-images.sh edge-monitor-jvm
#   bash deployment/build-push-images.sh edge-shopper-jvm
#   bash deployment/build-push-images.sh central-delivery-jvm
#   bash deployment/build-push-images.sh central-feeder-jvm
#   bash deployment/build-push-images.sh edge-manager-native  # GraalVM (lento; ver BACKLOG.md)
#   SKIP_PUSH=1 bash deployment/build-push-images.sh edge-manager-jvm
#
# Variables:
#   QUAY_ORG, SP_DEMO_PREFIX — ver deployment/sp-demo-images.env.sh
#   EDGE_MANAGER_JVM_TAG — por defecto edge-manager-jvm (homologado). publish-edge-manager-versioned.sh fija este tag y opcionalmente publica también :edge-manager-jvm-N.
#   EDGE_MONITOR_JVM_TAG / EDGE_SHOPPER_JVM_TAG / CENTRAL_DELIVERY_JVM_TAG / CENTRAL_FEEDER_JVM_TAG — default tags …-jvm.
#   CONTAINER_ENGINE — por defecto podman (export CONTAINER_ENGINE=docker si usas Docker)
#   SKIP_PUSH=1 — no ejecuta push
#   NATIVE_CONTAINER_PLATFORM — solo native: por defecto linux/amd64 (OpenShift x86_64). host = arquitectura local
#   JVM_CONTAINER_PLATFORM — solo JVM: por defecto linux/amd64 (imagen base acorde al clúster). host = sin --platform
#
set -euo pipefail

: "${CONTAINER_ENGINE:=podman}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=sp-demo-images.env.sh
source "${SCRIPT_DIR}/sp-demo-images.env.sh"

run_push() {
  if [[ "${SKIP_PUSH:-}" == "1" ]]; then
    echo "SKIP_PUSH=1 — omitiendo push de $1"
    return 0
  fi
  "${CONTAINER_ENGINE}" push "$1"
}

edge_manager_native() {
  echo "=== edge-manager (native / Mandrel en contenedor) → ${SP_IMAGE_EDGE_MANAGER_NATIVE}"
  cd "${REPO_ROOT}/camel/edge-manager"
  : "${NATIVE_CONTAINER_PLATFORM:=linux/amd64}"
  local mvn_extra=()
  local podman_extra=()
  if [[ "${NATIVE_CONTAINER_PLATFORM}" != "host" ]]; then
    echo "Plataforma nativa (Mandrel + imagen): ${NATIVE_CONTAINER_PLATFORM}"
    mvn_extra=(-Dquarkus.native.container-runtime-options="--platform=${NATIVE_CONTAINER_PLATFORM}")
    podman_extra=(--platform "${NATIVE_CONTAINER_PLATFORM}")
  else
    echo "NATIVE_CONTAINER_PLATFORM=host — binario para la arquitectura local (no forzar amd64)."
  fi
  ./mvnw -DskipTests -Dnative -Dquarkus.native.container-build=true "${mvn_extra[@]}" package
  "${CONTAINER_ENGINE}" build "${podman_extra[@]}" -f src/main/docker/Dockerfile.native -t "${SP_IMAGE_EDGE_MANAGER_NATIVE}" .
  run_push "${SP_IMAGE_EDGE_MANAGER_NATIVE}"
}

edge_manager_jvm() {
  echo "=== edge-manager (JVM) → ${SP_IMAGE_EDGE_MANAGER_JVM}"
  cd "${REPO_ROOT}/camel/edge-manager"
  ./mvnw -DskipTests package
  : "${JVM_CONTAINER_PLATFORM:=linux/amd64}"
  local podman_extra=()
  if [[ "${JVM_CONTAINER_PLATFORM}" != "host" ]]; then
    echo "Imagen contenedor JVM: --platform ${JVM_CONTAINER_PLATFORM}"
    podman_extra=(--platform "${JVM_CONTAINER_PLATFORM}")
  fi
  "${CONTAINER_ENGINE}" build "${podman_extra[@]}" -f src/main/docker/Dockerfile.jvm -t "${SP_IMAGE_EDGE_MANAGER_JVM}" .
  run_push "${SP_IMAGE_EDGE_MANAGER_JVM}"
}

edge_monitor_jvm() {
  echo "=== edge-monitor (JVM) → ${SP_IMAGE_EDGE_MONITOR_JVM}"
  cd "${REPO_ROOT}/camel/edge-monitor"
  ./mvnw -DskipTests package
  : "${JVM_CONTAINER_PLATFORM:=linux/amd64}"
  local podman_extra=()
  if [[ "${JVM_CONTAINER_PLATFORM}" != "host" ]]; then
    echo "Imagen contenedor JVM: --platform ${JVM_CONTAINER_PLATFORM}"
    podman_extra=(--platform "${JVM_CONTAINER_PLATFORM}")
  fi
  "${CONTAINER_ENGINE}" build "${podman_extra[@]}" -f src/main/docker/Dockerfile.jvm -t "${SP_IMAGE_EDGE_MONITOR_JVM}" .
  run_push "${SP_IMAGE_EDGE_MONITOR_JVM}"
}

edge_shopper_jvm() {
  echo "=== edge-shopper (JVM) → ${SP_IMAGE_EDGE_SHOPPER_JVM}"
  cd "${REPO_ROOT}/camel/edge-shopper"
  ./mvnw -DskipTests package
  : "${JVM_CONTAINER_PLATFORM:=linux/amd64}"
  local podman_extra=()
  if [[ "${JVM_CONTAINER_PLATFORM}" != "host" ]]; then
    echo "Imagen contenedor JVM: --platform ${JVM_CONTAINER_PLATFORM}"
    podman_extra=(--platform "${JVM_CONTAINER_PLATFORM}")
  fi
  "${CONTAINER_ENGINE}" build "${podman_extra[@]}" -f src/main/docker/Dockerfile.jvm -t "${SP_IMAGE_EDGE_SHOPPER_JVM}" .
  run_push "${SP_IMAGE_EDGE_SHOPPER_JVM}"
}

central_delivery_jvm() {
  echo "=== central-delivery (JVM) → ${SP_IMAGE_CENTRAL_DELIVERY_JVM}"
  cd "${REPO_ROOT}/camel/central-delivery"
  ./mvnw -DskipTests package
  : "${JVM_CONTAINER_PLATFORM:=linux/amd64}"
  local podman_extra=()
  if [[ "${JVM_CONTAINER_PLATFORM}" != "host" ]]; then
    echo "Imagen contenedor JVM: --platform ${JVM_CONTAINER_PLATFORM}"
    podman_extra=(--platform "${JVM_CONTAINER_PLATFORM}")
  fi
  "${CONTAINER_ENGINE}" build "${podman_extra[@]}" -f src/main/docker/Dockerfile.jvm -t "${SP_IMAGE_CENTRAL_DELIVERY_JVM}" .
  run_push "${SP_IMAGE_CENTRAL_DELIVERY_JVM}"
}

central_feeder_jvm() {
  echo "=== central-feeder (JVM) → ${SP_IMAGE_CENTRAL_FEEDER_JVM}"
  cd "${REPO_ROOT}/camel/central-feeder"
  ./mvnw -DskipTests package
  : "${JVM_CONTAINER_PLATFORM:=linux/amd64}"
  local podman_extra=()
  if [[ "${JVM_CONTAINER_PLATFORM}" != "host" ]]; then
    echo "Imagen contenedor JVM: --platform ${JVM_CONTAINER_PLATFORM}"
    podman_extra=(--platform "${JVM_CONTAINER_PLATFORM}")
  fi
  "${CONTAINER_ENGINE}" build "${podman_extra[@]}" -f src/main/docker/Dockerfile.jvm -t "${SP_IMAGE_CENTRAL_FEEDER_JVM}" .
  run_push "${SP_IMAGE_CENTRAL_FEEDER_JVM}"
}

print_targets() {
  echo "Objetivos conocidos: all | edge-manager-native | edge-manager-jvm | edge-monitor-jvm | edge-shopper-jvm | central-delivery-jvm | central-feeder-jvm"
}

case "${1:-all}" in
  all)
    edge_manager_jvm
    edge_monitor_jvm
    edge_shopper_jvm
    central_delivery_jvm
    central_feeder_jvm
    # Nativo: edge-manager-native (BACKLOG.md).
    ;;
  edge-manager-native)
    edge_manager_native
    ;;
  edge-manager-jvm)
    edge_manager_jvm
    ;;
  edge-monitor-jvm)
    edge_monitor_jvm
    ;;
  edge-shopper-jvm)
    edge_shopper_jvm
    ;;
  central-delivery-jvm)
    central_delivery_jvm
    ;;
  central-feeder-jvm)
    central_feeder_jvm
    ;;
  -h|--help|help)
    print_targets
    exit 0
    ;;
  *)
    echo "Objetivo desconocido: $1" >&2
    print_targets >&2
    exit 1
    ;;
esac

echo "Listo. Imagen(es) construidas$([[ "${SKIP_PUSH:-}" == "1" ]] && echo " (sin push)" || echo " y publicadas en Quay")."
