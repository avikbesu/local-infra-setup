#!/usr/bin/env bash
# =============================================================================
# scripts/kube-status.sh
# Cluster observability: status snapshot and log streaming.
#
# Usage:
#   ./scripts/kube-status.sh                               # full status snapshot
#   ./scripts/kube-status.sh logs <component> [flag]       # stream/dump pod logs
#     flag: --previous  (last crashed container)
#           --follow    (live tail)
#
# Called via:
#   make kube-status
#   make kube-logs COMPONENT=<name> [FLAG=--follow|--previous]
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/lib/kube-common.sh"

CMD="${1:-status}"

# ── Status snapshot ───────────────────────────────────────────────────────────
cmd_status() {
  require_yq
  require_kubectl
  require_helm

  local ctx cluster
  ctx=$(get_kind_context)
  cluster="${KIND_CLUSTER_NAME:-local-cluster}"

  log_step "Cluster"
  if kubectl cluster-info --context "$ctx" &>/dev/null; then
    kubectl cluster-info --context "$ctx" 2>/dev/null | grep "Kubernetes control plane"
    echo ""
    kubectl get nodes --context "$ctx" -o wide
  else
    log_warn "Cluster '${cluster}' is not running."
    return 0
  fi

  echo ""
  log_step "Helm Releases (enabled components)"
  local count i name namespace status
  count=$(count_enabled)

  for i in $(seq 0 $((count - 1))); do
    name=$(enabled_field "$i" name)
    namespace=$(enabled_field "$i" namespace)

    status=$(helm status "$name" -n "$namespace" -o json 2>/dev/null \
      | yq '.info.status' 2>/dev/null || echo "not-installed")

    case "$status" in
      deployed)      printf '  %b●%b %s (ns: %s) — %b%s%b\n' "$GREEN" "$RESET" "$name" "$namespace" "$GREEN" "$status" "$RESET" ;;
      not-installed) printf '  %b○%b %s (ns: %s) — %bnot installed%b\n' "$YELLOW" "$RESET" "$name" "$namespace" "$YELLOW" "$RESET" ;;
      *)             printf '  %b●%b %s (ns: %s) — %b%s%b\n' "$RED" "$RESET" "$name" "$namespace" "$RED" "$status" "$RESET" ;;
    esac
  done

  echo ""
  log_step "Pods (all namespaces)"
  kubectl get pods -A --context "$ctx" \
    --sort-by=.metadata.namespace \
    -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[0].ready'

  echo ""
  log_step "Port-Forward Processes"
  pgrep -a "kubectl port-forward" 2>/dev/null \
    | awk '{$1=""; print "  " $0}' \
    || echo "  (none running)"
}

# ── Log streaming ─────────────────────────────────────────────────────────────
cmd_logs() {
  require_yq
  require_kubectl

  local target="${2:-}" flag="${3:-}"
  local ctx
  ctx=$(get_kind_context)

  [[ -z "$target" ]] && { log_error "Usage: make kube-logs COMPONENT=<name>"; exit 1; }

  local namespace
  namespace=$(yq ".components[] | select(.name == \"$target\") | .namespace" \
    "$HELM_COMPONENTS_CONFIG" 2>/dev/null | head -1)

  [[ -z "$namespace" || "$namespace" == "null" ]] && \
    die "Component '${target}' not found in $HELM_COMPONENTS_CONFIG"

  log_step "Kube Logs: $target (ns: $namespace)"

  local -a kubectl_flags=(--tail=100 --context "$ctx" --prefix)
  [[ "$flag" == "--previous" ]] && kubectl_flags+=(--previous)
  [[ "$flag" == "--follow"   ]] && kubectl_flags+=(-f)

  local pod_list
  pod_list=$(list_component_pods "$target" "$namespace" \
    "NAME:.metadata.name")

  if [[ -z "$pod_list" ]]; then
    log_warn "No pods found for component '${target}' in namespace '${namespace}'."
    log_info "Check release status: make kube-status"
    exit 0
  fi

  while IFS= read -r pod; do
    log_info "── Pod: $pod ──"
    kubectl logs "$pod" -n "$namespace" "${kubectl_flags[@]}" 2>/dev/null || \
      log_warn "  Could not retrieve logs for $pod"
  done <<< "$pod_list"
}

# ── Dispatch ──────────────────────────────────────────────────────────────────
case "$CMD" in
  status) cmd_status ;;
  logs)   cmd_logs "$@" ;;
  *)
    log_error "Unknown command: '$CMD'"
    log_info "Usage: $0 [status|logs <component> [--follow|--previous]]"
    exit 1
    ;;
esac
