#!/usr/bin/env bash

set -Eeuo pipefail

CLUSTER_NAME="notes-cluster"

if k3d cluster list --no-headers | awk '{print $1}' | grep -qx "${CLUSTER_NAME}"; then
  printf 'El clúster %s ya existe; no se recrea.\n' "${CLUSTER_NAME}"
  kubectl config use-context "k3d-${CLUSTER_NAME}"
  exit 0
fi

for port in 18080 3000 9090; do
  if ss -ltnH "sport = :${port}" | grep -q .; then
    printf 'ERROR: el puerto %s está ocupado. No se crea el clúster.\n' "${port}" >&2
    ss -ltnp "sport = :${port}" >&2 || true
    exit 1
  fi
done

k3d cluster create "${CLUSTER_NAME}" \
  --servers 1 \
  --agents 2 \
  --k3s-arg '--disable=traefik@server:*' \
  -p '127.0.0.1:18080:80@loadbalancer' \
  -p '127.0.0.1:3000:3000@loadbalancer' \
  -p '127.0.0.1:9090:9090@loadbalancer' \
  --wait

kubectl config use-context "k3d-${CLUSTER_NAME}"
kubectl wait --for=condition=Ready nodes --all --timeout=180s
kubectl get nodes -o wide
