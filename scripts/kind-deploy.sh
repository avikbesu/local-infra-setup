#!/usr/bin/env bash
# =============================================================================
# scripts/kind-deploy.sh
# Lifecycle management for the local kind cluster.
#
# Usage:
#   ./scripts/kind-deploy.sh up   [cluster-name] [kind-config]
#   ./scripts/kind-deploy.sh down [cluster-name]
#   ./scripts/kind-deploy.sh status [cluster-name]
#
# Environment:
#   KIND_CLUSTER_NAME   — cluster name (default: local-cluster)
#   KIND_CONFIG         — path to kind config YAML (default: cluster/kind-config.yaml)
# =============================================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

CMD="${1:-up}"
CLUSTER_NAME="${2:-${KIND_CLUSTER_NAME:-local-cluster}}"
KIND_CONFIG="${3:-${REPO_ROOT}/cluster/kind-config.yaml}"

# ── Helpers ───────────────────────────────────────────────────────────────────
cluster_exists() {
  kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"
}

# ── UP ────────────────────────────────────────────────────────────────────────
cmd_up() {
  require_tool kind
  require_tool kubectl
  require_tool docker

  log_step "Kind Cluster Up"
  log_info "Cluster: ${BOLD}${CLUSTER_NAME}${RESET}"

  if cluster_exists; then
    log_info "Cluster '${CLUSTER_NAME}' already exists — skipping create."
  else
    if [[ -f "$KIND_CONFIG" ]]; then
      log_info "Creating cluster with config: $KIND_CONFIG"
      kind create cluster --name "$CLUSTER_NAME" --config "$KIND_CONFIG" --wait 60s
    else
      log_warn "Config file '$KIND_CONFIG' not found — creating cluster with defaults."
      kind create cluster --name "$CLUSTER_NAME" --wait 60s
    fi
    log_ok "Cluster '${CLUSTER_NAME}' created."
  fi

  kubectl cluster-info --context "kind-${CLUSTER_NAME}" &>/dev/null
  log_ok "kubectl context: kind-${CLUSTER_NAME}"

  echo ""
  log_info "Next steps:"
  log_info "  make kube-helm-repos    — register helm repositories"
  log_info "  make kube-secrets       — create K8s secrets from .env.local"
  log_info "  make kube-deploy        — deploy all enabled components"

  echo ""
  cmd_status
}

# ── DOWN ──────────────────────────────────────────────────────────────────────
cmd_down() {
  require_tool kind

  log_step "Kind Cluster Down"
  log_info "Cluster: ${BOLD}${CLUSTER_NAME}${RESET}"

  if cluster_exists; then
    kind delete cluster --name "$CLUSTER_NAME"
    log_ok "Cluster '${CLUSTER_NAME}' deleted."
  else
    log_warn "Cluster '${CLUSTER_NAME}' not found — nothing to delete."
  fi
}

# ── STATUS ────────────────────────────────────────────────────────────────────
cmd_status() {
  require_tool kind
  require_tool kubectl

  log_step "Kind Cluster Status"

  local clusters
  clusters=$(kind get clusters 2>/dev/null || true)
  if [[ -z "$clusters" ]]; then
    log_info "No kind clusters running."
    return 0
  fi

  log_info "Clusters:"
  echo "$clusters" | while IFS= read -r c; do
    echo "  $c"
  done

  if cluster_exists; then
    echo ""
    log_info "Nodes in '${CLUSTER_NAME}':"
    kubectl get nodes --context "kind-${CLUSTER_NAME}" -o wide 2>/dev/null || true
    echo ""
    log_info "Pods (all namespaces):"
    kubectl get pods --all-namespaces --context "kind-${CLUSTER_NAME}" 2>/dev/null || true
  fi
}

# ── Dispatch ──────────────────────────────────────────────────────────────────
case "$CMD" in
  up)     cmd_up ;;
  down)   cmd_down ;;
  status) cmd_status ;;
  *)
    log_error "Unknown command: '$CMD'"
    log_info "Usage: $0 <up|down|status> [cluster-name] [kind-config-path]"
    exit 1
    ;;
esac
