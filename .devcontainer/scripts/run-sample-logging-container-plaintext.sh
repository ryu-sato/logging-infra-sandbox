#!/usr/bin/env bash
# Demo: run one specific container whose logs Grafana Alloy picks up automatically
# (it discovers every Docker container via the Docker socket) and forwards to Loki.
# Emits plain text (non-JSON) log lines; see run-sample-logging-container-json.sh for the
# structured variant, for comparing structured vs. unstructured log handling in LogQL.
set -euo pipefail

LOKI_PORT=3100
CONTAINER_NAME="demo-logging-source-plaintext"

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
      level=INFO
      [ "$action" = "error" ] && level=ERROR
      ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      echo "$ts [$level] user=$user action=$action user action event"
      i=$((i+1))
      sleep 2
    done
  '

echo "Started ${CONTAINER_NAME}; Grafana Alloy will pick it up and forward to Loki."
echo "Each log line is plain text, e.g.: 2026-09-06T11:32:38Z [INFO] user=alice action=login user action event"
echo "Query it in Grafana (http://localhost:3000) Explore, or via:"
echo "  curl -sG http://localhost:${LOKI_PORT}/loki/api/v1/query_range --data-urlencode 'query={container=\"${CONTAINER_NAME}\"} |= \"action=login\"'"
