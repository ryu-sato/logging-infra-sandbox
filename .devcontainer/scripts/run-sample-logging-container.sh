#!/usr/bin/env bash
# Demo: run one specific container whose logs are forwarded to Loki via the
# Docker "loki" logging driver, instead of the default json-file driver.
set -euo pipefail

LOKI_PORT=3100
CONTAINER_NAME="demo-logging-source"

docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true

docker run -d \
  --name "${CONTAINER_NAME}" \
  --log-driver=loki \
  --log-opt loki-url="http://localhost:${LOKI_PORT}/loki/api/v1/push" \
  --log-opt loki-external-labels="job=devcontainer,container_name=${CONTAINER_NAME}" \
  busybox sh -c 'i=0; while true; do echo "sample log line $i"; i=$((i+1)); sleep 2; done'

echo "Started ${CONTAINER_NAME}, streaming to Loki."
echo "Query it in Grafana (http://localhost:3000) Explore, or via:"
echo "  curl -sG http://localhost:${LOKI_PORT}/loki/api/v1/query_range --data-urlencode 'query={container_name=\"${CONTAINER_NAME}\"}'"
