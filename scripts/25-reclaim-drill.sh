#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="quote-api-prod"
APP_NAME="quote-api"
INGRESS_URL="http://quote-api.local:31050"
TARGET_NODE="$(kubectl get pods -n "${NAMESPACE}" -l app="${APP_NAME}" -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' 2>/dev/null | awk 'NF' | sort -u | while read -r node; do if [[ "$(kubectl get node "${node}" -o jsonpath='{.metadata.labels.acme\.io/capacity}' 2>/dev/null)" == "spot" ]]; then echo "${node}"; break; fi; done)"

if [[ -z "${TARGET_NODE}" ]]; then
  TARGET_NODE="$(kubectl get nodes -l acme.io/capacity=spot --no-headers 2>/dev/null | awk 'NR==1 {print $1}')"
fi

if [[ -z "${TARGET_NODE}" ]]; then
  echo "No spot node found for reclaim drill" >&2
  exit 1
fi

echo "Using spot node ${TARGET_NODE} that currently hosts an app pod for reclaim drill"

echo "==> Draining node ${TARGET_NODE}"
kubectl drain "${TARGET_NODE}" --ignore-daemonsets --delete-emptydir-data --grace-period=20 --timeout=300s || true

cleanup() {
  echo "==> Uncordoning node ${TARGET_NODE}"
  kubectl uncordon "${TARGET_NODE}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "==> Waiting for replacement pods to appear"
kubectl -n "${NAMESPACE}" rollout status deployment/${APP_NAME} --timeout=300s

echo "==> Verifying service availability"
for i in $(seq 1 12); do
  if curl -fsS "${INGRESS_URL}/api/quote" >/tmp/quote-response.json 2>/dev/null; then
    echo "Request succeeded on attempt ${i}"
    cat /tmp/quote-response.json
    exit 0
  fi
  echo "Attempt ${i} failed; waiting"
  sleep 5
done

echo "Service did not respond after reclaim drill" >&2
exit 1
