#!/usr/bin/env bash
# Inferencia contra TensorFlow Serving (REST :predict).
# - SERVER: si no está definido, se obtiene de la Route tf-server (oc).
# - OC, EDGE1_NS: mismo criterio que el resto del demo (por defecto edge1).
set -euo pipefail

: "${OC:=oc}"
EDGE1_NS="${EDGE1_NS:-edge1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

image="${IMAGE:-./green.jpg}"

if [[ -z "${SERVER:-}" ]]; then
  host=$("$OC" get route tf-server -n "$EDGE1_NS" -o jsonpath='{.spec.host}' 2>/dev/null || true)
  if [[ -z "$host" ]]; then
    echo "No se pudo leer la Route tf-server en $EDGE1_NS. Define SERVER o ejecuta: oc get route tf-server -n $EDGE1_NS" >&2
    exit 1
  fi
  SERVER="https://${host}"
  echo "Usando SERVER=${SERVER} (desde oc)" >&2
fi

# macOS: base64 -i archivo | Linux GNU: base64 -w0 archivo
b64_file() {
  local f="$1"
  if b64_out=$(base64 -w0 "$f" 2>/dev/null); then
    printf '%s' "$b64_out"
    return
  fi
  base64 -i "$f" 2>/dev/null | tr -d '\n' || base64 <"$f" | tr -d '\n'
}

payload=$(printf '{"instances":[{"b64":"%s"}]}' "$(b64_file "$image")")

curl -sS -X POST \
  -H "content-type: application/json" \
  "${SERVER}/v1/models/tea_model_b64:predict" \
  -d "$payload"

echo
