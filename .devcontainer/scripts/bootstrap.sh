#!/usr/bin/env bash
# Idempotent devcontainer bootstrap: kind cluster + Loki + Grafana + Grafana Alloy.
# Runs on every container start (postStartCommand), so every step must be safe to repeat.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="${SCRIPT_DIR}/../k8s"
ALLOY_DIR="${SCRIPT_DIR}/../alloy"

CLUSTER_NAME="logging-sandbox"
NAMESPACE="monitoring"
GRAFANA_PORT=3000
LOKI_PORT=3100
ALLOY_CONTAINER="alloy"

log() { echo "[bootstrap] $*"; }

log "Waiting for the Docker daemon..."
for _ in $(seq 1 60); do
  docker info >/dev/null 2>&1 && break
  sleep 1
done
docker info >/dev/null 2>&1 || { log "Docker daemon never became ready"; exit 1; }

cluster_reachable() {
  kubectl --context "kind-${CLUSTER_NAME}" cluster-info >/dev/null 2>&1
}

if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  if cluster_reachable; then
    log "kind cluster '${CLUSTER_NAME}' already running"
  else
    log "kind cluster '${CLUSTER_NAME}' exists but is unreachable, recreating"
    kind delete cluster --name "${CLUSTER_NAME}"
    kind create cluster --name "${CLUSTER_NAME}" --wait 120s
  fi
else
  log "Creating kind cluster '${CLUSTER_NAME}'"
  kind create cluster --name "${CLUSTER_NAME}" --wait 120s
fi

kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null

log "Installing Loki + Grafana via Helm"
helm repo add grafana https://grafana.github.io/helm-charts --force-update >/dev/null
helm repo update grafana >/dev/null

helm upgrade --install loki grafana/loki \
  --namespace "${NAMESPACE}" --create-namespace \
  -f "${K8S_DIR}/loki-values.yaml" \
  --wait --timeout 5m

helm upgrade --install grafana grafana/grafana \
  --namespace "${NAMESPACE}" \
  -f "${K8S_DIR}/grafana-values.yaml" \
  --wait --timeout 5m

log "(Re)starting port-forwards for Loki (${LOKI_PORT}) and Grafana (${GRAFANA_PORT})"
pkill -f "kubectl .*port-forward.*${NAMESPACE}/svc/loki" >/dev/null 2>&1 || true
pkill -f "kubectl .*port-forward.*${NAMESPACE}/svc/grafana" >/dev/null 2>&1 || true

mkdir -p /tmp/devcontainer-logs
nohup kubectl --context "kind-${CLUSTER_NAME}" -n "${NAMESPACE}" port-forward --address 0.0.0.0 \
  svc/loki "${LOKI_PORT}:3100" >/tmp/devcontainer-logs/loki-port-forward.log 2>&1 &
disown

nohup kubectl --context "kind-${CLUSTER_NAME}" -n "${NAMESPACE}" port-forward --address 0.0.0.0 \
  svc/grafana "${GRAFANA_PORT}:80" >/tmp/devcontainer-logs/grafana-port-forward.log 2>&1 &
disown

log "Waiting for the Loki push API..."
for _ in $(seq 1 30); do
  curl -sf "http://localhost:${LOKI_PORT}/ready" >/dev/null 2>&1 && break
  sleep 1
done

log "(Re)starting Grafana Alloy (host-network container, tails all Docker container logs into Loki)"
docker rm -f "${ALLOY_CONTAINER}" >/dev/null 2>&1 || true
docker run -d \
  --name "${ALLOY_CONTAINER}" \
  --network host \
  --restart unless-stopped \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "${ALLOY_DIR}/config.alloy:/etc/alloy/config.alloy:ro" \
  grafana/alloy:latest \
  run --server.http.listen-addr=0.0.0.0:12345 /etc/alloy/config.alloy >/dev/null

log "Done."
log "Grafana:    http://localhost:${GRAFANA_PORT}  (admin/admin)"
log "Loki API:   http://localhost:${LOKI_PORT}"
log "Alloy UI:   http://localhost:12345"
log "Grafana Alloy tails every Docker container's logs automatically (job=devcontainer)."
log "See .devcontainer/scripts/run-sample-logging-container.sh for a working example."
