#!/usr/bin/env bash
# Demo: run one specific container whose logs Grafana Alloy picks up automatically
# (it discovers every Docker container via the Docker socket) and forwards to Loki.
# Emits JSON log lines; see run-sample-logging-container-plaintext.sh for the plain-text variant.
set -euo pipefail

LOKI_PORT=3100
CONTAINER_NAME="demo-logging-source-json"

docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true

docker run -d \
  --name "${CONTAINER_NAME}" \
  busybox sh -c '
    i=0
    while true; do
      case $((i % 4)) in
        0) user=alice ;;
        1) user=bob ;;
        2) user=carol ;;
        3) user=dave ;;
      esac
      case $((i % 5)) in
        0) action=login ;;
        1) action=view_page ;;
        2) action=purchase ;;
        3) action=logout ;;
        4) action=error ;;
      esac
      level=info
      [ "$action" = "error" ] && level=error
      ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      echo "{\"time\":\"$ts\",\"level\":\"$level\",\"username\":\"$user\",\"action\":\"$action\",\"msg\":\"user action event\"}"
      i=$((i+1))
      sleep 2
    done
  '

echo "Started ${CONTAINER_NAME}; Grafana Alloy will pick it up and forward to Loki."
echo "Each log line is a JSON object with username/action/level fields."
echo "Query it in Grafana (http://localhost:3000) Explore, or via:"
echo "  curl -sG http://localhost:${LOKI_PORT}/loki/api/v1/query_range --data-urlencode 'query={container=\"${CONTAINER_NAME}\"} | json | username=\"alice\"'"
