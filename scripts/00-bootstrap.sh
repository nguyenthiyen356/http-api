#!/usr/bin/env bash
# 00-bootstrap.sh — Create the k3d cluster and label nodes.
# Runs automatically as the toolbox container entrypoint.
# Safe to re-run: checks for existing cluster before creating.
set -euo pipefail

CLUSTER_NAME="acme"
NETWORK_NAME="k3d-acme-net"
API_PORT="6550"

echo "================================================================"
echo "  Bootstrap: k3d cluster '${CLUSTER_NAME}'"
echo "================================================================"

# ── Detect Docker host IP ─────────────────────────────────────────────────────
# Use the default-route gateway — that is the Docker host's IP on the bridge
# network, where the k3d API port is bound (0.0.0.0:${API_PORT} on the host).
# This avoids relying on container-name DNS (127.0.0.53 stub resolver fails
# from inside containers on Ubuntu systemd-resolved hosts).
HOST_IP=$(ip route | awk '/default/ {print $3; exit}')
if [[ -z "${HOST_IP}" ]]; then
  # Fallback: read gateway from Docker network inspect via the socket
  HOST_IP=$(docker network inspect "${NETWORK_NAME}" \
    --format '{{(index .IPAM.Config 0).Gateway}}' 2>/dev/null || true)
fi
if [[ -z "${HOST_IP}" ]]; then
  echo "ERROR: could not determine Docker host IP" >&2; exit 1
fi
echo "[bootstrap] Docker host IP: ${HOST_IP}"

# ── Create cluster (idempotent) ───────────────────────────────────────────────
CLUSTER_IS_NEW=false
if k3d cluster list 2>/dev/null | grep -q "^${CLUSTER_NAME}"; then
  echo "[bootstrap] Cluster '${CLUSTER_NAME}' already exists — skipping creation."
else
  echo "[bootstrap] Creating k3d cluster with 4 worker nodes..."
  k3d cluster create "${CLUSTER_NAME}" \
    --agents 4 \
    --network "${NETWORK_NAME}" \
    --api-port "0.0.0.0:${API_PORT}" \
    --port "8888:80@loadbalancer" \
    --k3s-arg "--tls-san=${HOST_IP}@server:0" \
    --wait \
    --timeout 180s
  echo "[bootstrap] Cluster created."
  CLUSTER_IS_NEW=true
fi

# ── Kubeconfig ────────────────────────────────────────────────────────────────
# Point kubectl at the host IP + exposed API port instead of the container name.
# The TLS cert was generated with HOST_IP as a SAN, so verification passes.
echo "[bootstrap] Writing kubeconfig (server: ${HOST_IP}:${API_PORT})..."
mkdir -p "${HOME}/.kube"
k3d kubeconfig get "${CLUSTER_NAME}" \
  | sed "s|https://0\.0\.0\.0:${API_PORT}|https://${HOST_IP}:${API_PORT}|g" \
  > "${HOME}/.kube/config"
chmod 600 "${HOME}/.kube/config"

# ── Wait for nodes ────────────────────────────────────────────────────────────
echo "[bootstrap] Waiting for all nodes to be Ready..."
kubectl wait --for=condition=Ready node --all --timeout=120s

# ── Label nodes to simulate production nodepools ─────────────────────────────
# Only run on first creation: prepare.sh is not idempotent across restarts
# (node ordering can change, causing label corruption on re-runs).
if [[ "${CLUSTER_IS_NEW}" == "true" ]]; then
  echo "[bootstrap] Running node preparation (spot / on-demand / GPU labels)..."
  bash /workspace/troubleshoot/prepare.sh
else
  echo "[bootstrap] Skipping prepare.sh (cluster already labeled)."
fi

echo ""
echo "[bootstrap] Done. Node layout:"
kubectl get nodes -L acme.io/capacity -L acme.io/node-type

# ── Export host-friendly kubeconfig ──────────────────────────────────────────────────
# Write a second kubeconfig using localhost:${API_PORT} so the Docker HOST can
# run 'kubectl' directly without docker exec.
# From the host: KUBECONFIG=.kube/config kubectl get node
# Or:            cp .kube/config ~/.kube/config
mkdir -p /workspace/.kube
k3d kubeconfig get "${CLUSTER_NAME}" \
  | sed "s|https://0\.0\.0\.0:${API_PORT}|https://localhost:${API_PORT}|g" \
  > /workspace/.kube/config
chmod 600 /workspace/.kube/config
echo "[bootstrap] Host kubeconfig written to .kube/config"
echo "[bootstrap]   Usage: KUBECONFIG=.kube/config kubectl get node"
echo ""
echo "[bootstrap] API accessible at: http://localhost:8888  (after deploy)"
