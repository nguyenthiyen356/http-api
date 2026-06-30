#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e
ARGOCD_NAMESPACE="argocd"

echo "=== 1. Creating ArgoCD Namespace ==="
kubectl create namespace ${ARGOCD_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

echo "=== 2. Applying ArgoCD ==="
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "=== 3. Waiting for ArgoCD Server to become Available ==="
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n ${ARGOCD_NAMESPACE}

kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort"}}'

ARGOCD_SERVER_PASSWORD=$(kubectl -n ${ARGOCD_NAMESPACE} get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

echo "--------------------------------------------------------"
echo "ArgoCD Installed Successfully!"
echo "--------------------------------------------------------"
echo "ArgoCD UI Authentication Credentials:"
echo "Username: admin"
echo "Password: ${ARGOCD_SERVER_PASSWORD}"
echo "--------------------------------------------------------"
