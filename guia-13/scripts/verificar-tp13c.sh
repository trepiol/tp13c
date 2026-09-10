#!/usr/bin/env bash

set -Eeuo pipefail

APP_NAMESPACE="devops-portfolio"
MON_NAMESPACE="monitoring"

INGRESS_URL="http://127.0.0.1:18080"
PROMETHEUS_URL="http://127.0.0.1:9090"
GRAFANA_URL="http://127.0.0.1:3000"

ERRORS=0

ok() {
  echo "[OK] $1"
}

fail() {
  echo "[ERROR] $1"
  ERRORS=$((ERRORS + 1))
}

section() {
  echo
  echo "=================================================="
  echo "$1"
  echo "=================================================="
}

section "1. Verificando nodos Kubernetes"

if kubectl get nodes --no-headers | awk '{print $2}' | grep -vq '^Ready$'; then
  fail "Hay nodos que no están Ready"
  kubectl get nodes
else
  ok "Todos los nodos están Ready"
fi


section "2. Verificando deployments"

DEPLOYMENTS=(
  "devops-portfolio:postgres"
  "devops-portfolio:backend"
  "devops-portfolio:frontend"
  "monitoring:prometheus"
  "monitoring:grafana"
)

for item in "${DEPLOYMENTS[@]}"; do
  namespace="${item%%:*}"
  deployment="${item##*:}"

  if kubectl rollout status \
      "deployment/${deployment}" \
      -n "${namespace}" \
      --timeout=30s >/dev/null 2>&1; then

    ok "Deployment ${namespace}/${deployment}"
  else
    fail "Deployment ${namespace}/${deployment}"
  fi
done


section "3. Verificando DaemonSets"

DAEMONSETS=(
  "node-exporter"
  "cadvisor"
)

for daemonset in "${DAEMONSETS[@]}"; do
  if kubectl rollout status \
      "daemonset/${daemonset}" \
      -n "${MON_NAMESPACE}" \
      --timeout=30s >/dev/null 2>&1; then

    ok "DaemonSet ${MON_NAMESPACE}/${daemonset}"
  else
    fail "DaemonSet ${MON_NAMESPACE}/${daemonset}"
  fi
done


section "4. Verificando Ingress"

if kubectl get ingress notes-app \
    -n "${APP_NAMESPACE}" >/dev/null 2>&1; then
  ok "Ingress notes-app existe"
else
  fail "Ingress notes-app no existe"
fi


section "5. Verificando PVCs"

for pvc in postgres-pvc zap-reports; do
  status="$(
    kubectl get pvc "${pvc}" \
      -n "${APP_NAMESPACE}" \
      -o jsonpath='{.status.phase}' 2>/dev/null || true
  )"

  if [[ "${status}" == "Bound" ]]; then
    ok "PVC ${pvc} está Bound"
  else
    fail "PVC ${pvc} no está Bound (estado: ${status:-no encontrado})"
  fi
done


section "6. Verificando aplicación vía Ingress"

if curl \
    --fail \
    --silent \
    --show-error \
    -H 'Host: notes.local' \
    "${INGRESS_URL}/health" >/dev/null; then

  ok "/health responde correctamente"
else
  fail "/health no responde correctamente"
fi


if curl \
    --fail \
    --silent \
    --show-error \
    -H 'Host: notes.local' \
    "${INGRESS_URL}/metrics" >/dev/null; then

  ok "/metrics responde correctamente"
else
  fail "/metrics no responde correctamente"
fi


section "7. Verificando Prometheus"

if curl \
    --fail \
    --silent \
    "${PROMETHEUS_URL}/-/ready" | grep -q "Prometheus Server is Ready"; then

  ok "Prometheus está Ready"
else
  fail "Prometheus no está Ready"
fi


TARGETS_JSON="$(
  curl --fail --silent \
    "${PROMETHEUS_URL}/api/v1/targets" 2>/dev/null || true
)"

if [[ -n "${TARGETS_JSON}" ]]; then

  DOWN_TARGETS="$(
    printf '%s' "${TARGETS_JSON}" |
      python3 -c '
import json
import sys

data = json.load(sys.stdin)

targets = data["data"]["activeTargets"]

down = [
    target for target in targets
    if target["health"] != "up"
]

print(len(down))
'
  )"

  if [[ "${DOWN_TARGETS}" == "0" ]]; then
    ok "Todos los targets activos de Prometheus están UP"
  else
    fail "Prometheus tiene ${DOWN_TARGETS} target(s) que no están UP"
  fi

else
  fail "No se pudo consultar /api/v1/targets"
fi


section "8. Verificando Grafana"

GRAFANA_HEALTH="$(
  curl --fail --silent \
    "${GRAFANA_URL}/api/health" 2>/dev/null || true
)"

if printf '%s' "${GRAFANA_HEALTH}" |
    grep -q '"database"[[:space:]]*:[[:space:]]*"ok"'; then

  ok "Grafana está saludable"
else
  fail "Grafana no está saludable"
fi


section "9. Verificando Job de OWASP ZAP"

ZAP_STATUS="$(
  kubectl get job zap-security-scan \
    -n "${APP_NAMESPACE}" \
    -o jsonpath='{.status.succeeded}' 2>/dev/null || true
)"

if [[ "${ZAP_STATUS}" == "1" ]]; then
  ok "Job zap-security-scan completado correctamente"
else
  fail "Job zap-security-scan no completó correctamente"
fi


section "10. Verificando reportes locales"

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

for report in \
  zap-k8s-report.html \
  zap-k8s-report.json
do

  if [[ -s "${ROOT_DIR}/reportes/${report}" ]]; then
    ok "Existe reportes/${report}"
  else
    fail "Falta reportes/${report}"
  fi
done


echo
echo "=================================================="

if (( ERRORS == 0 )); then
  echo "TP13C: todas las verificaciones pasaron"
  exit 0
else
  echo "TP13C: se encontraron ${ERRORS} error(es)"
  exit 1
fi
