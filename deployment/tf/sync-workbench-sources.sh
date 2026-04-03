#!/usr/bin/env bash
# Copia el directorio workbench/ del repo a /opt/app-root/src/workbench en el pod del Notebook wb1.
# Equivale a subir por la UI los .ipynb y retrain.pipeline sin el dataset grande.
#
# Requisitos: oc login, namespace tf, workbench wb1 en Running (app=wb1).
#
# Variables opcionales:
#   TF_NS            defecto: tf
#   WB_CONTAINER     defecto: wb1 (contenedor Jupyter, no kube-rbac-proxy)
#   OC               defecto: oc
#   SYNC_WAIT_SECS   defecto: 300 — espera a que el pod esté Ready
#
# Uso:
#   oc project tf
#   bash deployment/tf/sync-workbench-sources.sh
#
set -euo pipefail

: "${OC:=oc}"
: "${TF_NS:=tf}"
: "${WB_CONTAINER:=wb1}"
: "${SYNC_WAIT_SECS:=300}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WB_SRC="$REPO_ROOT/workbench"

if [[ ! -d "$WB_SRC" ]]; then
  echo "No se encuentra el directorio workbench: $WB_SRC" >&2
  exit 1
fi

"$OC" whoami >/dev/null 2>&1 || {
  echo "Inicia sesión con oc antes de ejecutar este script." >&2
  exit 1
}

POD=$("$OC" get pods -n "$TF_NS" -l app=wb1 -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -z "$POD" ]]; then
  echo "No hay ningún pod con label app=wb1 en el proyecto $TF_NS." >&2
  echo "Crea y arranca el workbench wb1 primero (consola o apply-notebook-wb1.sh)." >&2
  exit 1
fi

if ! "$OC" wait --for=condition=Ready "pod/$POD" -n "$TF_NS" --timeout="${SYNC_WAIT_SECS}s" 2>/dev/null; then
  echo "El pod $POD no llegó a Ready en ${SYNC_WAIT_SECS}s; comprueba: oc get pod -n $TF_NS -l app=wb1" >&2
  exit 1
fi

echo "Origen:  $WB_SRC"
echo "Destino: pod/$POD (-n $TF_NS -c $WB_CONTAINER) -> /opt/app-root/src/workbench"

# tar en el repo (solo workbench/) → tar en el pod bajo /opt/app-root/src
# En macOS, COPYFILE_DISABLE + --no-xattrs/--no-mac-metadata reducen cabeceras pax
# (p. ej. LIBARCHIVE.xattr.com.apple.provenance) que GNU tar del contenedor ignora y avisa.
# --warning=no-unknown-keyword silencia esas advertencias si aún aparecen.
(
  cd "$REPO_ROOT"
  if [[ "$(uname -s)" == "Darwin" ]]; then
    export COPYFILE_DISABLE=1
    tar cf - --no-xattrs --no-mac-metadata --exclude='.DS_Store' workbench
  else
    tar cf - --exclude='.DS_Store' workbench
  fi
) | "$OC" exec -i -n "$TF_NS" "$POD" -c "$WB_CONTAINER" -- \
  tar xf - --warning=no-unknown-keyword -C /opt/app-root/src

echo "Sincronización completada."
