#!/usr/bin/env bash
# Demo: run one specific container whose logs Grafana Alloy picks up automatically
# (it discovers every Docker container via the Docker socket) and forwards to Loki.
set -euo pipefail

LOKI_PORT=3100
CONTAINER_NAME="demo-logging-source"

docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true

docker run -d \
  --name "${CONTAINER_NAME}" \
  busybox sh -c 'i=0; while true; do echo "sample log line $i"; i=$((i+1)); sleep 2; done'

echo "Started ${CONTAINER_NAME}; Grafana Alloy will pick it up and forward to Loki."
echo "Query it in Grafana (http://localhost:3000) Explore, or via:"
echo "  curl -sG http://localhost:${LOKI_PORT}/loki/api/v1/query_range --data-urlencode 'query={container=\"${CONTAINER_NAME}\"}'"
