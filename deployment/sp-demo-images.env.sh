# Convención de imágenes — Solution Pattern: Edge-to-Core Data Pipelines for AI/ML
# Repo Git de referencia: sp-edge-to-cloud-data-pipelines-demo
#
# Un solo repositorio en Quay; cada componente de la demo usa un tag compuesto:
#   quay.io/${QUAY_ORG}/${SP_QUAY_REPOSITORY}:<componente>-<runtime>
# Ejemplos de tags: edge-manager-jvm, edge-monitor-jvm, edge-shopper-jvm, central-delivery-jvm, central-feeder-jvm, edge-manager-native, …
#
# Uso:
#   source deployment/sp-demo-images.env.sh
#   podman build -t "${SP_IMAGE_EDGE_MANAGER_JVM}" ...
#
# Variables:
#   QUAY_ORG (default cestayg)
#   SP_QUAY_REPOSITORY — nombre del repo en Quay (default sp-edge-to-cloud-data-pipelines-demo)
#   SP_DEMO_PREFIX — alias legado de SP_QUAY_REPOSITORY si solo exportas el prefijo antiguo

export QUAY_ORG="${QUAY_ORG:-cestayg}"
export SP_QUAY_REPOSITORY="${SP_QUAY_REPOSITORY:-${SP_DEMO_PREFIX:-sp-edge-to-cloud-data-pipelines-demo}}"
export CONTAINER_ENGINE="${CONTAINER_ENGINE:-podman}"

export SP_QUAY_IMAGE="quay.io/${QUAY_ORG}/${SP_QUAY_REPOSITORY}"
# Tag completo del componente (p. ej. edge-manager-jvm o edge-manager-jvm-12); ver deployment/publish-edge-manager-versioned.sh
export EDGE_MANAGER_JVM_TAG="${EDGE_MANAGER_JVM_TAG:-edge-manager-jvm}"
export SP_IMAGE_EDGE_MANAGER_JVM="${SP_QUAY_IMAGE}:${EDGE_MANAGER_JVM_TAG}"
export SP_IMAGE_EDGE_MANAGER_NATIVE="${SP_QUAY_IMAGE}:edge-manager-native"

export EDGE_MONITOR_JVM_TAG="${EDGE_MONITOR_JVM_TAG:-edge-monitor-jvm}"
export SP_IMAGE_EDGE_MONITOR_JVM="${SP_QUAY_IMAGE}:${EDGE_MONITOR_JVM_TAG}"

export EDGE_SHOPPER_JVM_TAG="${EDGE_SHOPPER_JVM_TAG:-edge-shopper-jvm}"
export SP_IMAGE_EDGE_SHOPPER_JVM="${SP_QUAY_IMAGE}:${EDGE_SHOPPER_JVM_TAG}"

export CENTRAL_DELIVERY_JVM_TAG="${CENTRAL_DELIVERY_JVM_TAG:-central-delivery-jvm}"
export SP_IMAGE_CENTRAL_DELIVERY_JVM="${SP_QUAY_IMAGE}:${CENTRAL_DELIVERY_JVM_TAG}"

export CENTRAL_FEEDER_JVM_TAG="${CENTRAL_FEEDER_JVM_TAG:-central-feeder-jvm}"
export SP_IMAGE_CENTRAL_FEEDER_JVM="${SP_QUAY_IMAGE}:${CENTRAL_FEEDER_JVM_TAG}"
