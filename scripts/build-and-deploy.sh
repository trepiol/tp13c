#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_NAME="notes-cluster"
CONTEXT="k3d-${CLUSTER_NAME}"

kubectl config use-context "${CONTEXT}"

docker build -t notes-backend:tp13c "${ROOT_DIR}/guia-06/app/backend"
docker build -t notes-frontend:tp13c "${ROOT_DIR}/guia-06/app/frontend"
k3d image import -c "${CLUSTER_NAME}" notes-backend:tp13c notes-frontend:tp13c

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx \
  --force-update
helm repo update
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.ingressClassResource.default=true \
  --wait --timeout 5m

kubectl apply -f "${ROOT_DIR}/guia-09/k8s/base/00-namespace.yaml"
kubectl apply -f "${ROOT_DIR}/guia-09/k8s/base/01-postgres.yaml"
kubectl rollout status deployment/postgres -n devops-portfolio --timeout=180s
kubectl apply -f "${ROOT_DIR}/guia-09/k8s/base/02-backend.yaml"
kubectl rollout status deployment/backend -n devops-portfolio --timeout=180s
kubectl apply -f "${ROOT_DIR}/guia-09/k8s/base/03-frontend.yaml"
kubectl rollout status deployment/frontend -n devops-portfolio --timeout=180s

kubectl apply -f "${ROOT_DIR}/guia-08/k8s/monitoring/05-prometheus.yaml"
kubectl apply -f "${ROOT_DIR}/guia-08/k8s/monitoring/06-node-exporter.yaml"
kubectl apply -f "${ROOT_DIR}/guia-08/k8s/monitoring/07-cadvisor.yaml"
kubectl apply -f "${ROOT_DIR}/guia-08/k8s/monitoring/08-grafana.yaml"

kubectl rollout status deployment/prometheus -n monitoring --timeout=180s
kubectl rollout status daemonset/node-exporter -n monitoring --timeout=180s
kubectl rollout status daemonset/cadvisor -n monitoring --timeout=180s
kubectl rollout status deployment/grafana -n monitoring --timeout=180s

kubectl get pods -n devops-portfolio -o wide
kubectl get pods -n monitoring -o wide
