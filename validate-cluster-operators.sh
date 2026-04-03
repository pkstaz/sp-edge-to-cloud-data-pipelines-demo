#!/usr/bin/env bash
# Preflight: compare installed operator CSVs vs versions this demo targets.
# Keep README.md "Cluster > Requirements" in sync with the REC_* variables below.
# En logs se usa "recomendado" (= objetivo del demo / README), no "testeado".
#
# Omitir toda la validación (código 0): SKIP_CLUSTER_VALIDATION=1  o  --skip
set -euo pipefail

# Iconos visibles en terminal moderna (UTF-8).
ICON_OK="✅"
ICON_MISSING="❌"
ICON_WARN="⚠️"
ICON_SECTION="▶"
ICON_DOT="●"

# Con dash/ash, los arrays fallan y set -u rompe el resumen; forzar bash explícito.
if [ -z "${BASH_VERSION:-}" ]; then
  echo "$ICON_MISSING Este script requiere bash (no ejecutar con sh). Ej.: bash \"$0\"" >&2
  exit 1
fi

if [[ "${SKIP_CLUSTER_VALIDATION:-}" == "1" ]] || [[ "${1:-}" == "--skip" ]]; then
  echo "$ICON_SECTION Validación de cluster/operadores omitida (SKIP_CLUSTER_VALIDATION=1 o --skip)." >&2
  exit 0
fi

: "${OC:=oc}"
command -v "$OC" >/dev/null || { echo "$ICON_MISSING oc not in PATH"; exit 1; }
command -v jq >/dev/null || { echo "$ICON_MISSING jq required"; exit 1; }

REC_CLUSTER_MINOR="4.20"
REC_ODF_PATTERN="odf-operator"
REC_ODF_VER="4.20"
REC_RHOAI_PATTERN="ods-operator"
REC_RHOAI_VER="3.3.0"
REC_PIPE_PATTERN="openshift-pipelines-operator"
REC_PIPE_VER="1.21.1"
# Variantes de nombre CSV (OperatorHub / OLM): p. ej. amqstreams.v… vs amq-streams-cluster-operator…
REC_KAFKA_PATTERN="amqstreams|amq-streams"
REC_KAFKA_VER="3.1.0"
REC_BROKER_PATTERN="amq-broker"
REC_BROKER_VER="7.12"
REC_CAMEL_PATTERN="camel-k-operator|camel-k|camel-k-community"
# Community Camel K 2.x (2.9, 2.10, …); substring match on CSV name/version — excludes Red Hat 1.x line
REC_CAMEL_VER="2."
REC_SKUPPER_PATTERN="skupper-operator"
REC_SKUPPER_VER="2.1.3"

# Proveedor mostrado en logs (como en OperatorHub / CSV).
PROVIDER_REDHAT="Red Hat"
PROVIDER_APACHE="The Apache Software Foundation"

# jsonpath evita JSON completo: algunos CSV traen anotaciones/descripciones con
# caracteres de control y jq falla con "control characters ... must be escaped".
CSV_LINES=$("$OC" get csv -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.status.phase}{"\t"}{.spec.version}{"\t"}{.metadata.creationTimestamp}{"\n"}{end}' 2>/dev/null) \
  || { echo "$ICON_MISSING cannot list CSVs (logged in? cluster up?)"; exit 1; }

# $1 = uno o varios substrings separados por | (cualquiera que case en metadata.name del CSV).
pick_csv() {
  local patterns_arg="$1"
  local IFS='|'
  local -a patterns
  read -ra patterns <<<"$patterns_arg"
  unset IFS
  local pattern_lc name_lc best_line="" best_ts="" pat matched
  while IFS=$'\t' read -r ns name phase ver cts || [[ -n "$ns" ]]; do
    [[ "$phase" == "Succeeded" ]] || continue
    name_lc=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')
    matched=0
    for pat in "${patterns[@]}"; do
      pat=$(printf '%s' "$pat" | tr '[:upper:]' '[:lower:]')
      [[ -z "$pat" ]] && continue
      if [[ "$name_lc" == *"$pat"* ]]; then
        matched=1
        break
      fi
    done
    [[ "$matched" -eq 1 ]] || continue
    if [[ -z "$best_ts" ]] || [[ "$cts" > "$best_ts" ]]; then
      best_ts="$cts"
      best_line="$ns $name ${ver:-}"
    fi
  done <<<"$CSV_LINES"
  [[ -n "$best_line" ]] && printf '%s\n' "$best_line"
}

# Expone __csv_ver para el resumen (mismo patrón que la línea de cluster).
check_pair() {
  local pattern="$1" want="$2"
  local line ns name ver
  __csv_ver=""
  line=$(pick_csv "$pattern") || true
  if [[ -z "${line:-}" ]]; then
    __status="missing"
    return 1
  fi
  read -r ns name ver <<<"$line"
  __csv_ver="${ver:-—}"
  if [[ "$name" == *"$want"* ]] || [[ "$ver" == *"$want"* ]]; then
    __status="ok"
  else
    __status="warn"
  fi
  return 0
}

rc=0

echo "$ICON_SECTION === Cluster ==="
ver=$("$OC" version -o json 2>/dev/null | jq -r '.openshiftVersion // empty' || true)
if [[ -n "$ver" ]]; then
  if [[ "$ver" == "${REC_CLUSTER_MINOR}"* ]]; then
    echo "$ICON_OK OpenShift $ver · recomendado: ${REC_CLUSTER_MINOR}.x"
  else
    echo "$ICON_WARN OpenShift $ver · recomendado: ${REC_CLUSTER_MINOR}.x"
    rc=1
  fi
else
  echo "$ICON_WARN OpenShift — sin openshiftVersion · recomendado: ${REC_CLUSTER_MINOR}.x"
  rc=1
fi

glance_ok=()
glance_issue=()

# $1 título (como en operador), $2 proveedor, $3 patrón CSV, $4 versión recomendada (fragmento README)
run_check() {
  local title="$1" vendor="$2" pattern="$3" want="$4"
  __status=
  if check_pair "$pattern" "$want"; then
    # if/elif: con set -e, [[ … ]] && … falla en falso y aborta el script.
    if [[ "$__status" == "ok" ]]; then
      glance_ok+=("$ICON_OK $title provided by $vendor · $__csv_ver · recomendado: $want")
    elif [[ "$__status" == "warn" ]]; then
      glance_issue+=("$ICON_WARN $title provided by $vendor · $__csv_ver · recomendado: $want")
      rc=1
    fi
  else
    rc=1
    glance_issue+=("$ICON_MISSING $title provided by $vendor · no instalado · recomendado: $want")
  fi
}

run_check "OpenShift Data Foundation" "$PROVIDER_REDHAT" "$REC_ODF_PATTERN" "$REC_ODF_VER"
run_check "OpenShift AI" "$PROVIDER_REDHAT" "$REC_RHOAI_PATTERN" "$REC_RHOAI_VER"
run_check "OpenShift Pipelines" "$PROVIDER_REDHAT" "$REC_PIPE_PATTERN" "$REC_PIPE_VER"
run_check "Streams for Apache Kafka" "$PROVIDER_REDHAT" "$REC_KAFKA_PATTERN" "$REC_KAFKA_VER"
run_check "Red Hat Integration - AMQ Broker for RHEL 8 (Multiarch)" "$PROVIDER_REDHAT" "$REC_BROKER_PATTERN" "$REC_BROKER_VER"
run_check "Camel K Operator" "$PROVIDER_APACHE" "$REC_CAMEL_PATTERN" "$REC_CAMEL_VER"
run_check "Red Hat Service Interconnect" "$PROVIDER_REDHAT" "$REC_SKUPPER_PATTERN" "$REC_SKUPPER_VER"

echo
echo "$ICON_SECTION === Operaators ==="
if [[ ${#glance_ok[@]} -gt 0 ]]; then
  for g in "${glance_ok[@]}"; do echo "$g"; done
fi
if [[ ${#glance_issue[@]} -gt 0 ]]; then
  for g in "${glance_issue[@]}"; do echo "$g"; done
fi
if [[ ${#glance_ok[@]} -eq 0 && ${#glance_issue[@]} -eq 0 ]]; then
  echo "$ICON_WARN (sin datos)"
fi

exit "$rc"
