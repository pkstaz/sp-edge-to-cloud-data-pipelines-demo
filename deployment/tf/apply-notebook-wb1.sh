#!/usr/bin/env bash
# Aplica PVC wb1-storage + Notebook wb1 en tf, alineado con la consola de OpenShift AI
# (inject-auth, imagen en registry interno, envFrom dc1, tamaño Medium, volúmenes Elyra/CA).
#
# Variables opcionales:
#   NOTEBOOK_IS_NS   namespace de ImageStreams y referencia interna (defecto: redhat-ods-applications)
#   WORKBENCH_IMAGE  si está definida, se usa tal cual (saltar ref. interna por IS:tag)
#   WORKBENCH_ISTAG  p.ej. tensorflow:2025.2
#   WORKBENCH_TAG    preferencia de tag numérico (defecto: 2025.2)
#   WORKBENCH_ACCEL  cuda por defecto; rocm solo en AMD
#   WORKBENCH_HW_PROFILE  nombre HardwareProfile (defecto: default-profile); vacío omite anotaciones HW
#   OC               cliente OpenShift (defecto: oc)
#
# Uso:
#   oc project tf
#   bash deployment/tf/apply-notebook-wb1.sh
#
set -euo pipefail

: "${OC:=oc}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_NS=tf
NOTEBOOK_IS_NS="${NOTEBOOK_IS_NS:-redhat-ods-applications}"
WORKBENCH_TAG="${WORKBENCH_TAG:-2025.2}"
WORKBENCH_ACCEL="${WORKBENCH_ACCEL:-cuda}"
WORKBENCH_HW_PROFILE="${WORKBENCH_HW_PROFILE:-default-profile}"
TEMPLATE="$SCRIPT_DIR/notebook-wb1.yaml"
PVC_MANIFEST="$SCRIPT_DIR/workbench-pvc-wb1.yaml"
RENDER_PY="$SCRIPT_DIR/render_notebook_wb1.py"

"$OC" whoami >/dev/null 2>&1 || {
  echo "Inicia sesión con oc antes de ejecutar este script." >&2
  exit 1
}

discover_workbench_istag() {
  local ns="$NOTEBOOK_IS_NS"
  local is disp tag tags accel
  accel=$(printf '%s' "$WORKBENCH_ACCEL" | tr '[:upper:]' '[:lower:]')
  while IFS= read -r is; do
    [[ -z "$is" ]] && continue
    disp=$("$OC" get imagestream "$is" -n "$ns" -o jsonpath='{.metadata.annotations.opendatahub\.io/notebook-image-name}' 2>/dev/null || true)
    echo "$disp" | grep -qi 'tensorflow' || continue
    echo "$disp" | grep -qiE 'python.*3\.12|3\.12' || continue
    case "$accel" in
      cuda)
        echo "$disp" | grep -qi 'cuda' || continue
        echo "$disp" | grep -qi 'rocm' && continue
        ;;
      rocm)
        echo "$disp" | grep -qi 'rocm' || continue
        echo "$disp" | grep -qi 'cuda' && continue
        ;;
      *)
        echo "WORKBENCH_ACCEL debe ser rocm o cuda (valor: $WORKBENCH_ACCEL)" >&2
        return 1
        ;;
    esac
    tags=$("$OC" get imagestream "$is" -n "$ns" -o jsonpath='{range .spec.tags[*]}{.name}{"\n"}{end}' 2>/dev/null || true)
    if echo "$tags" | grep -qx "$WORKBENCH_TAG"; then
      echo "${is}:${WORKBENCH_TAG}"
      return 0
    fi
    if echo "$tags" | grep -qx '2025.1'; then
      echo "${is}:2025.1"
      return 0
    fi
    tag=$(echo "$tags" | grep -E '^202[0-9]' | head -1 || true)
    if [[ -n "$tag" ]]; then
      echo "${is}:${tag}"
      return 0
    fi
  done < <("$OC" get imagestream -n "$ns" -l opendatahub.io/notebook-image=true -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
  return 1
}

internal_image_ref_from_istag() {
  local istag="$1"
  local ns="$NOTEBOOK_IS_NS"
  local is_name tag_part
  is_name=${istag%%:*}
  tag_part=${istag#*:}
  echo "image-registry.openshift-image-registry.svc:5000/${ns}/${is_name}:${tag_part}"
}

notebook_build_commit_from_istag() {
  local istag="$1"
  local ns="$NOTEBOOK_IS_NS"
  "$OC" get imagestreamtag "$istag" -n "$ns" -o jsonpath='{.tag.annotations.opendatahub\.io/notebook-build-commit}' 2>/dev/null || true
}

hardware_profile_resource_version() {
  local name="$1"
  [[ -z "$name" ]] && return 0
  "$OC" get hardwareprofile "$name" -n "$NOTEBOOK_IS_NS" -o jsonpath='{.metadata.resourceVersion}' 2>/dev/null || true
}

OPENSHIFT_USER=$("$OC" whoami)

if [[ -n "${WORKBENCH_IMAGE:-}" ]]; then
  WB_IMAGE=$WORKBENCH_IMAGE
  ISTAG_FOR_ANN=${WORKBENCH_ISTAG:-unknown:unknown}
  DISP_NAME="${IMAGE_DISPLAY_NAME:-Jupyter | TensorFlow | CUDA | Python 3.12}"
  GIT_COMMIT="${WORKBENCH_GIT_COMMIT:-}"
  HW_RV="${WORKBENCH_HW_PROFILE_RV:-$(hardware_profile_resource_version "$WORKBENCH_HW_PROFILE")}"
else
  if [[ -n "${WORKBENCH_ISTAG:-}" ]]; then
    ISTAG=$WORKBENCH_ISTAG
  else
    if ! ISTAG=$(discover_workbench_istag); then
      echo "No se encontró un ImageStream TensorFlow + Python 3.12 + ${WORKBENCH_ACCEL} en -n $NOTEBOOK_IS_NS." >&2
      echo "Para AMD/ROCm: export WORKBENCH_ACCEL=rocm" >&2
      echo "Lista: oc get imagestream -n $NOTEBOOK_IS_NS -l opendatahub.io/notebook-image=true" >&2
      exit 1
    fi
  fi
  WB_IMAGE=$(internal_image_ref_from_istag "$ISTAG")
  ISTAG_FOR_ANN=$ISTAG
  IS_NAME=${ISTAG%%:*}
  DISP_NAME=$("$OC" get imagestream "$IS_NAME" -n "$NOTEBOOK_IS_NS" -o jsonpath='{.metadata.annotations.opendatahub\.io/notebook-image-name}' 2>/dev/null || true)
  [[ -z "$DISP_NAME" ]] && DISP_NAME="Jupyter | TensorFlow | CUDA | Python 3.12"
  GIT_COMMIT=$(notebook_build_commit_from_istag "$ISTAG")
  HW_RV=$(hardware_profile_resource_version "$WORKBENCH_HW_PROFILE")
fi

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

if command -v python3 >/dev/null 2>&1; then
  export TEMPLATE TMP WB_IMAGE ISTAG_FOR_ANN DISP_NAME OPENSHIFT_USER NOTEBOOK_IS_NS
  export GIT_COMMIT HW_RV WORKBENCH_HW_PROFILE
  python3 "$RENDER_PY" || exit 1
else
  echo "Se requiere python3 para generar el manifiesto del Notebook." >&2
  exit 1
fi

echo "WORKBENCH_ACCEL=$WORKBENCH_ACCEL"
echo "Imagen (registry interno): $WB_IMAGE"
echo "Anotación last-image-selection: $ISTAG_FOR_ANN"
[[ -n "$GIT_COMMIT" ]] && echo "Build commit (ISTag): $GIT_COMMIT"
[[ -n "$HW_RV" ]] && echo "HardwareProfile $WORKBENCH_HW_PROFILE resourceVersion: $HW_RV"

"$OC" apply -f "$PVC_MANIFEST"
"$OC" apply -f "$TMP"

echo "Espera a que el Notebook esté listo: oc get notebook wb1 -n $TF_NS -o wide && oc get pods -n $TF_NS -l app=wb1"
