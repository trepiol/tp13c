#!/usr/bin/env bash

set -Eeuo pipefail

NAMESPACE="devops-portfolio"
PVC="zap-reports"
POD="zap-report-extractor"

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_DIR="${ROOT_DIR}/reportes"

mkdir -p "${REPORT_DIR}"

echo "[+] Eliminando extractor anterior si existe..."

kubectl delete pod "${POD}" \
  -n "${NAMESPACE}" \
  --ignore-not-found=true >/dev/null

echo "[+] Creando pod auxiliar..."

kubectl run "${POD}" \
  -n "${NAMESPACE}" \
  --image=busybox:1.36 \
  --restart=Never \
  --overrides="
{
  \"spec\": {
    \"containers\": [
      {
        \"name\": \"${POD}\",
        \"image\": \"busybox:1.36\",
        \"command\": [\"sh\", \"-c\", \"sleep 3600\"],
        \"volumeMounts\": [
          {
            \"name\": \"reports\",
            \"mountPath\": \"/reports\"
          }
        ]
      }
    ],
    \"volumes\": [
      {
        \"name\": \"reports\",
        \"persistentVolumeClaim\": {
          \"claimName\": \"${PVC}\"
        }
      }
    ]
  }
}" >/dev/null

echo "[+] Esperando que el pod quede Ready..."

kubectl wait \
  --for=condition=Ready \
  "pod/${POD}" \
  -n "${NAMESPACE}" \
  --timeout=180s

echo "[+] Copiando reportes..."

kubectl cp \
  "${NAMESPACE}/${POD}:/reports/zap-k8s-report.html" \
  "${REPORT_DIR}/zap-k8s-report.html"

kubectl cp \
  "${NAMESPACE}/${POD}:/reports/zap-k8s-report.json" \
  "${REPORT_DIR}/zap-k8s-report.json"

echo "[+] Eliminando pod auxiliar..."

kubectl delete pod "${POD}" \
  -n "${NAMESPACE}" >/dev/null

echo
echo "[+] Reportes extraidos:"
ls -lh "${REPORT_DIR}"
