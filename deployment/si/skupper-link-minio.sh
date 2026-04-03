#!/usr/bin/env bash
# Red Hat Service Interconnect (Skupper): enlace central↔edge1 y exposición de MinIO como minio-central.
# Soporta CLI Skupper v1 (init, token create, link create, anotación) y v2 / RHSI 2.x
# (site create, token issue/redeem, connector + listener).
#
# Requisitos: oc login, skupper CLI en PATH, operador RHSI instalado,
#             proyectos central y edge1, MinIO en central (minio-service).
#
# Variables: OC, CENTRAL_NS, EDGE1_NS, TOKEN_FILE (por defecto <repo>/edge-to-central.token; .gitignore)
# Nota v2: el nombre del fichero solo puede usar [A-Za-z0-9./~-] (sin guiones bajos).
# Sitios v2: SKUPPER_SITE_CENTRAL (default demo-central), SKUPPER_SITE_EDGE (default demo-edge1)
#
set -euo pipefail

: "${OC:=oc}"
CENTRAL_NS="${CENTRAL_NS:-central}"
EDGE1_NS="${EDGE1_NS:-edge1}"
SKUPPER_SITE_CENTRAL="${SKUPPER_SITE_CENTRAL:-demo-central}"
SKUPPER_SITE_EDGE="${SKUPPER_SITE_EDGE:-demo-edge1}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TOKEN_FILE="${TOKEN_FILE:-${REPO_ROOT}/edge-to-central.token}"

command -v skupper >/dev/null 2>&1 || {
  echo "skupper CLI no está en PATH. Instálalo: curl https://skupper.io/install.sh | sh" >&2
  echo "  y export PATH=\"\$HOME/.local/bin:\$PATH\" (Linux) o el path que indique el instalador." >&2
  exit 1
}

"$OC" whoami &>/dev/null || {
  echo "Inicia sesión con oc antes de continuar." >&2
  exit 1
}

for ns in "$CENTRAL_NS" "$EDGE1_NS"; do
  if ! "$OC" get namespace "$ns" &>/dev/null; then
    echo "Namespace $ns no existe. Créalo antes (p. ej. install-demo-steps.sh)." >&2
    exit 1
  fi
done

if ! "$OC" get svc minio-service -n "$CENTRAL_NS" &>/dev/null; then
  echo "No hay minio-service en $CENTRAL_NS. Despliega MinIO central primero." >&2
  exit 1
fi

skupper_cli_family() {
  # v2: «site create»; v1: «init»
  if skupper site create --help &>/dev/null; then
    echo v2
  elif skupper init --help &>/dev/null; then
    echo v1
  else
    echo unknown
  fi
}

run_skupper_v1() {
  echo "Skupper CLI v1: init en $CENTRAL_NS (consola + token)..."
  "$OC" project "$CENTRAL_NS"
  skupper init --enable-console --enable-flow-collector --console-auth unsecured
  skupper token create "$TOKEN_FILE"

  echo "Skupper CLI v1: init y link en $EDGE1_NS..."
  "$OC" project "$EDGE1_NS"
  skupper init
  skupper link create "$TOKEN_FILE" --name edge-to-central

  echo "Skupper CLI v1: anotar MinIO central como minio-central..."
  "$OC" project "$CENTRAL_NS"
  "$OC" annotate service minio-service skupper.io/proxy=http skupper.io/address=minio-central --overwrite
}

skupper_site_exists() {
  "$OC" get sites.skupper.io -n "$1" -o name 2>/dev/null | grep -q .
}

run_skupper_v2() {
  echo "Skupper CLI v2 (RHSI): sitio en $CENTRAL_NS con link access + token..."
  "$OC" project "$CENTRAL_NS"
  if ! skupper_site_exists "$CENTRAL_NS"; then
    skupper site create "$SKUPPER_SITE_CENTRAL" --enable-link-access --wait ready
  else
    echo "  Ya hay un Site en $CENTRAL_NS; habilitando link access si hace falta..."
    skupper site update --enable-link-access --wait ready || true
  fi
  skupper token issue "$TOKEN_FILE" --expiration-window 24h --redemptions-allowed 3

  echo "Skupper CLI v2: sitio en $EDGE1_NS y canje del token (link)..."
  "$OC" project "$EDGE1_NS"
  if ! skupper_site_exists "$EDGE1_NS"; then
    skupper site create "$SKUPPER_SITE_EDGE" --wait ready
  else
    echo "  Ya hay un Site en $EDGE1_NS."
  fi
  skupper token redeem "$TOKEN_FILE"

  # v2: el Connector exige un Listener con la misma routing key; crear primero el Listener en edge.
  echo "Skupper CLI v2: Listener minio-central:9000 en $EDGE1_NS (antes del connector)..."
  "$OC" project "$EDGE1_NS"
  skupper listener delete minio-central 2>/dev/null || \
    "$OC" delete listeners.skupper.io minio-central -n "$EDGE1_NS" --ignore-not-found --wait=true 2>/dev/null || true
  # configured = aplicado al router; no exige aún el connector (--wait ready fallaría aquí).
  skupper listener create minio-central 9000 --wait configured

  echo "Skupper CLI v2: Connector MinIO API (puerto 9000) en $CENTRAL_NS..."
  "$OC" project "$CENTRAL_NS"
  skupper connector delete minio-central 2>/dev/null || \
    "$OC" delete connectors.skupper.io minio-central -n "$CENTRAL_NS" --ignore-not-found --wait=true 2>/dev/null || true
  skupper connector create minio-central 9000 --selector app=minio --wait ready

  echo "Skupper CLI v2: esperando Listener Ready en $EDGE1_NS..."
  "$OC" project "$EDGE1_NS"
  deadline=$((SECONDS + 300))
  lst=""
  while ((SECONDS < deadline)); do
    lst=$("$OC" get listeners.skupper.io minio-central -n "$EDGE1_NS" -o jsonpath='{.status.status}' 2>/dev/null || true)
    if [[ "$lst" == "Ready" ]]; then
      echo "  Listener minio-central: Ready"
      break
    fi
    sleep 4
  done
  if [[ "${lst:-}" != "Ready" ]]; then
    echo "  Aviso: Listener no llegó a Ready en 300s (status=${lst:-?}). Revisa: oc get listener,connector -n $EDGE1_NS $CENTRAL_NS" >&2
  fi
}

family=$(skupper_cli_family)
case "$family" in
  v1) run_skupper_v1 ;;
  v2) run_skupper_v2 ;;
  *)
    echo "No se reconoce la familia de comandos de skupper (ni v1 «init» ni v2 «site create»)." >&2
    echo "  Actualiza la CLI: https://skupper.io/install.sh — y comprueba: skupper version" >&2
    exit 1
    ;;
esac

echo "Listo. En $EDGE1_NS debería existir el servicio minio-central (puerto 9000 API S3)."
echo "  Prueba (opcional consola MinIO puerto 9090): oc project $EDGE1_NS && oc create route edge minio-central-demo --service=minio-central --port=port9090"
echo "  Elimina la ruta de prueba: oc delete route minio-central-demo -n $EDGE1_NS --ignore-not-found"
