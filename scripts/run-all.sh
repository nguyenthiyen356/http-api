#!/usr/bin/env bash
# run-all.sh — Run every numbered script in order inside the toolbox container.
# Execute on the HOST after `docker compose up -d`.
# Usage: ./scripts/run-all.sh
set -euo pipefail

TOOLBOX="toolbox"

echo "================================================================"
echo "  Waiting for toolbox cluster bootstrap to complete..."
echo "================================================================"
for i in $(seq 1 60); do   # 60 × 10s = 10 min max
  if docker exec "${TOOLBOX}" kubectl get nodes --no-headers 2>/dev/null \
       | grep -q " Ready"; then
    echo "  Cluster is ready."
    break
  fi
  if [[ "${i}" -eq 60 ]]; then
    echo "ERROR: cluster never became ready. Check: docker logs ${TOOLBOX}"
    exit 1
  fi
  echo "  [${i}/60] waiting for cluster..."
  sleep 10
done

echo ""
# Run every script whose name starts with one or more digits followed by '-'
# 00-bootstrap.sh is excluded (it already ran as container entrypoint)
for script in scripts/[1-9][0-9]-*.sh; do
  [[ -f "${script}" ]] || continue
  echo ""
  echo "========================================================"
  echo "  Running: ${script}"
  echo "========================================================"
  docker exec "${TOOLBOX}" bash "/workspace/${script}"
done

echo ""
echo "========================================================"
echo "  All scripts completed successfully."
echo "  API: http://localhost:8888/api/quote"
echo "========================================================"
