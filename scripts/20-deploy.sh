#!/usr/bin/env bash
# 20-deploy.sh — Install ArgoCD and deploy quote-api via an ArgoCD Application.
# The Application syncs the Helm chart from the GitHub repo automatically.
# Safe to re-run: kubectl apply is idempotent; ArgoCD re-syncs on each run.
set -euo pipefail

ARGOCD_NS="argocd"
ARGOCD_VERSION="v2.10.2"
APP_NAME="quote-api"

echo "================================================================"
echo "  Deploy: ArgoCD + quote-api GitOps Application"
echo "================================================================"

# ── Install ArgoCD ────────────────────────────────────────────────────────────
echo "[deploy] Installing ArgoCD ${ARGOCD_VERSION}..."
kubectl create namespace "${ARGOCD_NS}" --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -n "${ARGOCD_NS}" \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

echo "[deploy] Waiting for ArgoCD server to be ready (up to 3 min)..."
kubectl rollout status deployment/argocd-server \
  -n "${ARGOCD_NS}" --timeout=180s

# ── Determine image tag ───────────────────────────────────────────────────────
# Use current git SHA so ArgoCD deploys exactly what was built by CI.
IMAGE_TAG=$(git -C /workspace rev-parse --short HEAD 2>/dev/null || echo "latest")
echo "[deploy] Image tag: ${IMAGE_TAG}"

# ── Apply ArgoCD Application (with image tag substituted) ────────────────────
echo "[deploy] Applying ArgoCD Application..."
sed "s/__IMAGE_TAG__/${IMAGE_TAG}/g" /workspace/gitops/application.yaml \
  | kubectl apply -f -

# ── Wait for sync and health ──────────────────────────────────────────────────
echo "[deploy] Waiting for Application to sync and become healthy..."
for i in $(seq 1 36); do   # 36 × 10s = 6 min max
  SYNC=$(kubectl get application "${APP_NAME}" -n "${ARGOCD_NS}" \
    -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
  HEALTH=$(kubectl get application "${APP_NAME}" -n "${ARGOCD_NS}" \
    -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")

  echo "  [${i}/36] Sync=${SYNC}  Health=${HEALTH}"

  if [[ "${SYNC}" == "Synced" && "${HEALTH}" == "Healthy" ]]; then
    echo "[deploy] Application is Synced and Healthy."
    break
  fi

  if [[ "${i}" -eq 36 ]]; then
    echo "[deploy] ERROR: Application did not become healthy in time."
    kubectl get application "${APP_NAME}" -n "${ARGOCD_NS}" -o yaml | tail -30
    exit 1
  fi
  sleep 10
done

# ── Show pod placement ────────────────────────────────────────────────────────
echo ""
echo "[deploy] Pod placement across nodepools:"
kubectl get pods -n "${APP_NAME}" -o wide

echo ""
echo "================================================================"
echo "  Done! Service reachable at: http://localhost:8888/api/quote"
echo "================================================================"
