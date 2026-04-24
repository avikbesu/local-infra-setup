#!/usr/bin/env bash
# =============================================================================
# scripts/kube-logs.sh
# Streams or dumps logs for all pods belonging to a named Helm component.
# Namespace is resolved automatically from cluster/helm-components.yaml.
#
# Usage:
#   ./scripts/kube-logs.sh <component>              # tail logs (last 100 lines)
#   ./scripts/kube-logs.sh <component> --previous   # logs from last crashed container
#   ./scripts/kube-logs.sh <component> --follow     # follow (stream) live logs
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/lib/kube-common.sh"

require_yq
require_kubectl

TARGET="${1:-}"
FLAG="${2:-}"
CLUSTER_NAME="${KIND_CLUSTER_NAME:-local-cluster}"
CTX="kind-${CLUSTER_NAME}"

[[ -z "$TARGET" ]] && { log_error "Usage: make kube-logs COMPONENT=<name>"; exit 1; }

# ── Resolve namespace from registry ──────────────────────────────────────────
NAMESPACE=$(yq ".components[] | select(.name == \"$TARGET\") | .namespace" \
  "$HELM_COMPONENTS_CONFIG" 2>/dev/null | head -1)

[[ -z "$NAMESPACE" || "$NAMESPACE" == "null" ]] && \
  die "Component '${TARGET}' not found in $HELM_COMPONENTS_CONFIG"

log_step "Kube Logs: $TARGET (ns: $NAMESPACE)"

# ── Build kubectl flags ───────────────────────────────────────────────────────
KUBECTL_FLAGS=(--tail=100 --context "$CTX" --prefix)
[[ "$FLAG" == "--previous" ]] && KUBECTL_FLAGS+=(--previous)
[[ "$FLAG" == "--follow"   ]] && KUBECTL_FLAGS+=(-f)

# ── Stream logs for each pod of this release ──────────────────────────────────
pod_list=$(kubectl get pods -n "$NAMESPACE" \
  -l "app.kubernetes.io/instance=${TARGET}" \
  --context "$CTX" \
  --no-headers \
  -o custom-columns='NAME:.metadata.name' \
  2>/dev/null || true)

if [[ -z "$pod_list" ]]; then
  log_warn "No pods found for component '${TARGET}' in namespace '${NAMESPACE}'."
  log_info "Check release status: make kube-status"
  exit 0
fi

while IFS= read -r pod; do
  log_info "── Pod: $pod ──"
  kubectl logs "$pod" -n "$NAMESPACE" "${KUBECTL_FLAGS[@]}" 2>/dev/null || \
    log_warn "  Could not retrieve logs for $pod"
done <<< "$pod_list"
