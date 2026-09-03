#!/usr/bin/env bash
# Idempotent devcontainer bootstrap: kind cluster + Loki + Grafana + Loki docker log driver.
# Runs on every container start (postStartCommand), so every step must be safe to repeat.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="${SCRIPT_DIR}/../k8s"

CLUSTER_NAME="logging-sandbox"
NAMESPACE="monitoring"
GRAFANA_PORT=3000
LOKI_PORT=3100

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

log "Installing the Loki Docker logging-driver plugin"
if ! docker plugin ls --format '{{.Name}}' | grep -qx "loki:latest"; then
  docker plugin install grafana/loki-docker-driver:latest --alias loki --grant-all-permissions
fi

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

log "Done."
log "Grafana:  http://localhost:${GRAFANA_PORT}  (admin/admin)"
log "Loki API: http://localhost:${LOKI_PORT}"
log "Forward a specific container's logs to Loki with:"
log "  docker run --log-driver=loki --log-opt loki-url=http://localhost:${LOKI_PORT}/loki/api/v1/push ..."
log "See .devcontainer/scripts/run-sample-logging-container.sh for a working example."
