#!/usr/bin/env bash
# ============================================================
# scripts/kind-deploy.sh
# Provision a kind cluster and deploy the analytics stack into it.
# Usage: kind-deploy.sh <up|down|status> [cluster-name] [kind-config]
# ============================================================
set -euo pipefail

CMD="${1:-up}"
CLUSTER_NAME="${2:-local-cluster}"
KIND_CONFIG="${3:-../cluster/kind-config.yaml}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPOSE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Helpers ──────────────────────────────────────────────────
require() {
  command -v "$1" >/dev/null 2>&1 || { echo "❌ Required tool '$1' not found. Install it first."; exit 1; }
}

cluster_exists() {
  kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"
}

# ── UP ────────────────────────────────────────────────────────
cmd_up() {
  require kind
  require kubectl
  require docker

  echo "🔧 USE_KIND=true — provisioning kind cluster: ${CLUSTER_NAME}"

  # 1. Create cluster if it doesn't exist
  if cluster_exists; then
    echo "  ✅ Cluster '${CLUSTER_NAME}' already exists — skipping create."
  else
    echo "  Creating cluster '${CLUSTER_NAME}'..."
    if [ -f "$KIND_CONFIG" ]; then
      echo "  Using config: $KIND_CONFIG"
      kind create cluster --name "$CLUSTER_NAME" --config "$KIND_CONFIG" --wait 60s
    else
      echo "  ⚠️  Config file '$KIND_CONFIG' not found, creating cluster with defaults."
      kind create cluster --name "$CLUSTER_NAME" --wait 60s
    fi
    echo "  ✅ Cluster created."
  fi

  # 2. Set kubectl context
  kubectl cluster-info --context "kind-${CLUSTER_NAME}" >/dev/null
  echo "  ✅ kubectl context set to kind-${CLUSTER_NAME}"

  # 3. Load images into kind (avoids registry pulls inside cluster)
  echo ""
  echo "📦 Loading images into kind cluster (this may take a minute)..."
  IMAGES=(
    "minio/minio:latest"
    "minio/mc:latest"
    "postgres:16-alpine"
    "tabulario/iceberg-rest:0.10.0"
    "trinodb/trino:435"
  )
  for img in "${IMAGES[@]}"; do
    echo "  Pulling $img locally..."
    docker pull "$img" --quiet
    echo "  Loading $img into kind..."
    kind load docker-image "$img" --name "$CLUSTER_NAME"
  done
  echo "  ✅ Images loaded."

  # 4. Apply k8s manifests generated from compose (via kompose if available,
  #    else fall back to docker compose inside the cluster via docker)
  echo ""
  if command -v kompose >/dev/null 2>&1; then
    echo "🚀 Deploying via kompose..."
    cd "$COMPOSE_DIR"
    KUBECONFIG_CTX="kind-${CLUSTER_NAME}"
    kompose convert -f docker-compose.yml -f docker-compose.override.yml \
      --out /tmp/kind-manifests --controller deployment 2>/dev/null
    kubectl apply --context "$KUBECONFIG_CTX" -f /tmp/kind-manifests/ -n analytics --create-namespace
    rm -rf /tmp/kind-manifests
    echo "  ✅ Deployed to kind cluster."
    echo ""
    echo "🚀 Stack deploying to kind cluster '${CLUSTER_NAME}':"
    echo "   Run: kubectl port-forward svc/trino 8080:8080 -n analytics"
    echo "   Run: kubectl port-forward svc/minio 9001:9001 -n analytics"
  else
    # Fallback: run compose on the host (kind cluster provisioned, analytics via compose)
    echo "ℹ️  kompose not found — analytics stack will run via Docker Compose on the host."
    echo "   (The kind cluster is provisioned and ready for Airflow / other helm charts.)"
    echo "   Install kompose for full in-cluster deployment: https://kompose.io/installation/"
    echo ""
    cd "$COMPOSE_DIR"
    docker compose -f docker-compose.yml -f docker-compose.override.yml up -d --remove-orphans
    echo ""
    echo "🚀 Stack is up (host compose + kind cluster ready):"
    echo "   Trino UI      → http://localhost:${TRINO_PORT:-8080}"
    echo "   Iceberg REST  → http://localhost:${ICEBERG_REST_PORT:-8181}"
    echo "   MinIO Console → http://localhost:${MINIO_CONSOLE_PORT:-9001}"
  fi

  echo ""
  cmd_status
}

# ── DOWN ──────────────────────────────────────────────────────
cmd_down() {
  require kind

  echo "🛑 Tearing down kind cluster: ${CLUSTER_NAME}"

  # Also stop compose if running
  cd "$COMPOSE_DIR"
  docker compose -f docker-compose.yml -f docker-compose.override.yml down 2>/dev/null || true

  if cluster_exists; then
    kind delete cluster --name "$CLUSTER_NAME"
    echo "  ✅ Cluster '${CLUSTER_NAME}' deleted."
  else
    echo "  ⚠️  Cluster '${CLUSTER_NAME}' not found — nothing to delete."
  fi
}

# ── STATUS ────────────────────────────────────────────────────
cmd_status() {
  require kind
  require kubectl

  echo "📋 Kind clusters:"
  kind get clusters 2>/dev/null || echo "  (none)"

  if cluster_exists; then
    echo ""
    echo "📋 Nodes in '${CLUSTER_NAME}':"
    kubectl get nodes --context "kind-${CLUSTER_NAME}" 2>/dev/null || true
    echo ""
    echo "📋 Pods (all namespaces):"
    kubectl get pods --all-namespaces --context "kind-${CLUSTER_NAME}" 2>/dev/null || true
  fi
}

# ── Dispatch ──────────────────────────────────────────────────
case "$CMD" in
  up)     cmd_up ;;
  down)   cmd_down ;;
  status) cmd_status ;;
  *)
    echo "Usage: $0 <up|down|status> [cluster-name] [kind-config-path]"
    exit 1
    ;;
esac
