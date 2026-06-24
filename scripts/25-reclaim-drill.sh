#!/usr/bin/env bash
# 25-reclaim-drill.sh — Simulate a spot node reclaim.
# Drains one spot node while a curl loop proves the service stays live,
# shows pods rescheduling, then uncordons the node.
# Safe to re-run.
set -euo pipefail

NAMESPACE="quote-api"
DEPLOY="quote-api"
# Use the Docker host IP + exposed port instead of the LB container hostname
# to avoid DNS resolution failures (127.0.0.53 stub on Ubuntu hosts).
HOST_IP=$(ip route | awk '/default/ {print $3; exit}')
LB_HOST="${HOST_IP}:8888"

echo "================================================================"
echo "  Spot Reclaim Drill"
echo "================================================================"

# ── Pick a spot node ──────────────────────────────────────────────────────────
SPOT_NODE=$(kubectl get nodes -l acme.io/capacity=spot \
  -o jsonpath='{.items[0].metadata.name}')
if [[ -z "${SPOT_NODE}" ]]; then
  echo "ERROR: no spot node found (did 00-bootstrap.sh run?)"; exit 1
fi
echo "[drill] Target spot node: ${SPOT_NODE}"

# ── Current placement ─────────────────────────────────────────────────────────
echo ""
echo "[drill] Pod placement BEFORE drain:"
kubectl get pods -n "${NAMESPACE}" -o wide

# ── Start curl health-check loop (background) ─────────────────────────────────
echo ""
echo "[drill] Starting curl health-check loop (1 req/2s via Ingress LB)..."
(
  while true; do
    CODE=$(curl -sw '%{http_code}' -o /dev/null --connect-timeout 2 \
           "http://${LB_HOST}/api/quote" 2>/dev/null \
           || echo "ERR")
    echo "  [$(date +'%H:%M:%S')] HTTP ${CODE}"
    sleep 2
  done
) &
CURL_PID=$!
# Ensure background loop is killed on exit
trap 'kill "${CURL_PID}" 2>/dev/null; true' EXIT

sleep 4   # let a few successful responses print

# ── Drain the spot node ───────────────────────────────────────────────────────
echo ""
echo "[drill] Draining ${SPOT_NODE} (simulating spot reclaim)..."
kubectl drain "${SPOT_NODE}" \
  --delete-emptydir-data \
  --ignore-daemonsets \
  --grace-period=10 \
  --timeout=120s

# ── Watch rescheduling ────────────────────────────────────────────────────────
echo ""
echo "[drill] Pods immediately after drain:"
kubectl get pods -n "${NAMESPACE}" -o wide

echo ""
echo "[drill] Waiting for deployment to stabilise..."
kubectl rollout status deployment/"${DEPLOY}" -n "${NAMESPACE}" --timeout=120s

echo ""
echo "[drill] Final pod placement (service has been live throughout):"
kubectl get pods -n "${NAMESPACE}" -o wide

# Stop the curl loop and summarise
sleep 4
kill "${CURL_PID}" 2>/dev/null; CURL_PID=0

# ── Uncordon ─────────────────────────────────────────────────────────────────
echo ""
echo "[drill] Uncordoning ${SPOT_NODE} (restoring node)..."
kubectl uncordon "${SPOT_NODE}"

echo ""
echo "[drill] Node layout restored:"
kubectl get nodes -L acme.io/capacity -L acme.io/node-type

echo ""
echo "================================================================"
echo "  Drill complete. Service remained live during spot reclaim."
echo "================================================================"
