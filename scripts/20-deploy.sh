#!/usr/bin/env bash

set -euo pipefail

ARGOCD_NAMESPACE="argocd"
APP_NAMESPACE="quote-api-prod"
APP_NAME="quote-api"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_MANIFEST="${REPO_ROOT}/scripts/quote-api-argo-app.yaml"

echo "=== 1. Creating ArgoCD Namespace ==="
kubectl create namespace "${ARGOCD_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "=== 2. Installing ArgoCD ==="
kubectl apply -n "${ARGOCD_NAMESPACE}" --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "=== 3. Waiting for ArgoCD Services to become Available ==="
kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n "${ARGOCD_NAMESPACE}"
kubectl wait --for=condition=available --timeout=600s deployment/argocd-repo-server -n "${ARGOCD_NAMESPACE}"

kubectl patch svc argocd-server -n "${ARGOCD_NAMESPACE}" -p '{"spec": {"type": "NodePort"}}'

echo "=== 4. Creating application namespace ==="
kubectl create namespace "${APP_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "=== 5. Creating ArgoCD Application for quote-api ==="
kubectl apply -f "${APP_MANIFEST}"

echo "=== 6. Waiting for the quote-api deployment to roll out ==="
kubectl -n "${APP_NAMESPACE}" rollout status deployment/${APP_NAME} --timeout=600s

ARGOCD_SERVER_PASSWORD=$(kubectl -n "${ARGOCD_NAMESPACE}" get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

echo "--------------------------------------------------------"
echo "ArgoCD Installed Successfully!"
echo "--------------------------------------------------------"
echo "ArgoCD UI Authentication Credentials:"
echo "Username: admin"
echo "Password: ${ARGOCD_SERVER_PASSWORD}"
echo "Application: ${APP_NAME} deployed in namespace ${APP_NAMESPACE}"
echo "--------------------------------------------------------"
