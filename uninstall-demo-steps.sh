#!/usr/bin/env bash
# Rollback inverso a install-demo-steps.sh: elimina en cluster lo que el install crea.
# Mantén este archivo alineado: por cada bloque nuevo en install, añade aquí el reverso
# (orden inverso: primero lo último que se despliega).
#
# Uso (tras oc login):
#   bash uninstall-demo-steps.sh
#
# No borra el cluster RHDP ni desinstala operadores; solo recursos del demo en namespaces.
# Edge1: por defecto se elimina el proyecto/namespace completo (MinIO, AMQ, Skupper, edge-manager, edge-monitor, edge-shopper, tf-server, rutas).
#        Mantener edge1 y borrar solo piezas: SKIP_EDGE1_PROJECT_DELETE=1 (y opcionalmente los SKIP_* de abajo).
# Saltar borrado explícito Tekton (pipeline, triggers, SA pipeline): SKIP_TEKTON_UNINSTALL=1
# Saltar borrado ruta + ActiveMQArtemis en edge1 (solo si SKIP_EDGE1_PROJECT_DELETE=1): SKIP_EDGE1_AMQ_UNINSTALL=1
# Saltar borrado MinIO en edge1 (solo si SKIP_EDGE1_PROJECT_DELETE=1): SKIP_EDGE1_MINIO_UNINSTALL=1
# Saltar borrado Camel K price-engine / plataforma en edge1 (solo si SKIP_EDGE1_PROJECT_DELETE=1): SKIP_EDGE1_CAMEL_K_UNINSTALL=1
# Saltar borrado Edge Monitor en edge1 (solo si SKIP_EDGE1_PROJECT_DELETE=1): SKIP_EDGE_MONITOR_UNINSTALL=1
# Saltar borrado Edge Shopper en edge1 (solo si SKIP_EDGE1_PROJECT_DELETE=1): SKIP_EDGE_SHOPPER_UNINSTALL=1
# EDGE1_NS=edge1 — namespace edge (alinear con install-demo-steps.sh)
#
set -euo pipefail

if [ -z "${BASH_VERSION:-}" ]; then
  echo "Este script requiere bash. Ej.: bash \"$0\"" >&2
  exit 1
fi

: "${OC:=oc}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_NS=tf
EDGE1_NS="${EDGE1_NS:-edge1}"

"$OC" whoami >/dev/null 2>&1 || {
  echo "Inicia sesión con oc antes de desinstalar: oc login …" >&2
  exit 1
}

# =============================================================================
# Edge1 — proyecto completo (MinIO, AMQ, Skupper, edge-manager, edge-monitor, edge-shopper, tf-server, Camel K, rutas)
# =============================================================================
if [[ "${SKIP_EDGE1_PROJECT_DELETE:-}" != "1" ]]; then
  if "$OC" get project "$EDGE1_NS" &>/dev/null; then
    echo "Eliminando proyecto $EDGE1_NS (todos los recursos del demo en edge) …"
    "$OC" delete project "$EDGE1_NS" --wait=true
  elif "$OC" get namespace "$EDGE1_NS" &>/dev/null; then
    echo "Eliminando namespace $EDGE1_NS …"
    "$OC" delete namespace "$EDGE1_NS" --wait=true
  else
    echo "Proyecto/namespace $EDGE1_NS no existe; nada que borrar (edge1)."
  fi
else
  # Modo granular: conservar el proyecto edge1 y quitar solo lo que instaló el demo.
  if ! "$OC" get namespace "$EDGE1_NS" &>/dev/null; then
    echo "Namespace $EDGE1_NS no existe; omitiendo desinstalación granular en edge1."
  else
    echo "SKIP_EDGE1_PROJECT_DELETE=1: borrando recursos sueltos en $EDGE1_NS …"
    "$OC" delete route tf-server -n "$EDGE1_NS" --ignore-not-found --wait=true
    "$OC" delete svc tf-server -n "$EDGE1_NS" --ignore-not-found --wait=true
    "$OC" delete deployment tf-server -n "$EDGE1_NS" --ignore-not-found --wait=true
    "$OC" delete deployment edge-manager -n "$EDGE1_NS" --ignore-not-found --wait=true
    "$OC" delete svc edge-manager -n "$EDGE1_NS" --ignore-not-found --wait=true
    if [[ "${SKIP_EDGE_MONITOR_UNINSTALL:-}" != "1" ]]; then
      "$OC" delete deployment edge-monitor -n "$EDGE1_NS" --ignore-not-found --wait=true
      "$OC" delete svc edge-monitor -n "$EDGE1_NS" --ignore-not-found --wait=true
    fi
    if [[ "${SKIP_EDGE_SHOPPER_UNINSTALL:-}" != "1" ]]; then
      "$OC" delete route camel-edge -n "$EDGE1_NS" --ignore-not-found --wait=true
      "$OC" delete deployment edge-shopper -n "$EDGE1_NS" --ignore-not-found --wait=true
      "$OC" delete svc edge-shopper -n "$EDGE1_NS" --ignore-not-found --wait=true
      # Legacy name (antes del rename a edge-shopper)
      "$OC" delete deployment shopper svc shopper -n "$EDGE1_NS" --ignore-not-found --wait=false
    fi
    if [[ "${SKIP_EDGE1_MINIO_UNINSTALL:-}" != "1" ]]; then
      "$OC" delete route minio-ui minio-api -n "$EDGE1_NS" --ignore-not-found --wait=true
      "$OC" delete deployment minio -n "$EDGE1_NS" --ignore-not-found --wait=true
      "$OC" delete svc minio-service -n "$EDGE1_NS" --ignore-not-found --wait=true
      "$OC" delete pvc minio-pvc -n "$EDGE1_NS" --ignore-not-found --wait=true
      "$OC" delete secret minio-secret -n "$EDGE1_NS" --ignore-not-found --wait=true
    fi
    if [[ "${SKIP_EDGE1_AMQ_UNINSTALL:-}" != "1" ]]; then
      "$OC" delete route broker-amq-mqtt -n "$EDGE1_NS" --ignore-not-found --wait=true
      "$OC" delete activemqartemis broker-amq -n "$EDGE1_NS" --ignore-not-found --wait=true
    fi
    if [[ "${SKIP_EDGE1_CAMEL_K_UNINSTALL:-}" != "1" ]]; then
      echo "Borrando Camel K price-engine y recursos asociados en $EDGE1_NS …"
      "$OC" delete integration/price-engine integrationplatform/camel-k secret/camel-k-registry configmap/catalogue \
        route/price-engine svc/price-engine -n "$EDGE1_NS" --ignore-not-found --wait=false
      "$OC" delete integrationkit --all -n "$EDGE1_NS" --wait=false 2>/dev/null || true
      "$OC" delete builds.camel.apache.org --all -n "$EDGE1_NS" --wait=false 2>/dev/null || true
    fi
  fi
fi

# =============================================================================
# 3. Tekton / OpenShift Pipelines (train-model) — reverso
# =============================================================================
# Mismo orden lógico inverso al apply: runs → pipeline → triggers → RBAC.
# Omitir: SKIP_TEKTON_UNINSTALL=1 (p. ej. si ya borraste a mano)
if [[ "${SKIP_TEKTON_UNINSTALL:-}" != "1" ]] && "$OC" get namespace "$TF_NS" &>/dev/null; then
  "$OC" delete pipelinerun --all -n "$TF_NS" --ignore-not-found --wait=false 2>/dev/null || true
  "$OC" delete taskrun --all -n "$TF_NS" --ignore-not-found --wait=false 2>/dev/null || true
  "$OC" delete pipeline train-model -n "$TF_NS" --ignore-not-found --wait=true
  "$OC" delete eventlistener train-model-listener -n "$TF_NS" --ignore-not-found --wait=true
  "$OC" delete triggertemplate train-model-template -n "$TF_NS" --ignore-not-found --wait=true
  "$OC" delete triggerbinding train-model-binding -n "$TF_NS" --ignore-not-found --wait=true
  "$OC" delete rolebinding pipeline-edit -n "$TF_NS" --ignore-not-found --wait=true
  "$OC" delete serviceaccount pipeline -n "$TF_NS" --ignore-not-found --wait=true
fi

# =============================================================================
# 2. Create and prepare a RHOAI project — reverso
# =============================================================================

# 2.3 README — Data Science project tf (antes que central: orden inverso al install)
# 2.3a Workbench Notebook wb1, DSPA, PVCs, Secret dc1 — README (explícito; el proyecto borra el resto)
if "$OC" get namespace "$TF_NS" &>/dev/null; then
  "$OC" delete notebook wb1 -n "$TF_NS" --ignore-not-found
  "$OC" delete pvc wb1-storage -n "$TF_NS" --ignore-not-found
  "$OC" delete pvc wb1 -n "$TF_NS" --ignore-not-found
  "$OC" delete datasciencepipelinesapplication dspa -n "$TF_NS" --ignore-not-found --wait=true
  "$OC" delete pvc pipeline-pvc -n "$TF_NS" --ignore-not-found
  "$OC" delete secret dc1 -n "$TF_NS" --ignore-not-found
fi
if "$OC" get project "$TF_NS" &>/dev/null; then
  echo "Eliminando proyecto $TF_NS …"
  "$OC" delete project "$TF_NS" --wait=true
elif "$OC" get namespace "$TF_NS" &>/dev/null; then
  echo "Eliminando namespace $TF_NS …"
  "$OC" delete namespace "$TF_NS" --wait=true
else
  echo "Proyecto/namespace $TF_NS no existe; nada que borrar (2.3)."
fi

# 2.1 README § central — quitar proyecto (MinIO, Kafka Strimzi, central-delivery, central-feeder, PVC, routes, …)
CENTRAL_NS=central
if "$OC" get project "$CENTRAL_NS" &>/dev/null; then
  echo "Eliminando proyecto $CENTRAL_NS …"
  "$OC" delete project "$CENTRAL_NS" --wait=true
elif "$OC" get namespace "$CENTRAL_NS" &>/dev/null; then
  echo "Eliminando namespace $CENTRAL_NS …"
  "$OC" delete namespace "$CENTRAL_NS" --wait=true
else
  echo "Proyecto/namespace $CENTRAL_NS no existe; nada que borrar (2.1)."
fi

# Buckets MinIO desaparecen con el namespace (datos en el PVC del proyecto).

# =============================================================================
# 1. Provision — no aplicable (el cluster sigue en RHDP)
# =============================================================================

echo "Desinstalación local del script completada (revisa namespaces si quedó alguno en Terminating)."
