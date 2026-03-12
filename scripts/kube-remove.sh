#!/usr/bin/env bash
# =============================================================================
# scripts/kube-remove.sh
# Uninstalls Helm releases for all enabled components in
# cluster/helm-components.yaml (in reverse deployment order).
#
# Usage:
#   ./scripts/kube-remove.sh             # remove all enabled releases
#   ./scripts/kube-remove.sh <name>      # remove a single named release
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/lib/kube-common.sh"

require_yq
require_helm
require_kubectl

TARGET="${1:-}"

log_step "Kube Remove"
log_info "Config: $HELM_COMPONENTS_CONFIG"
[[ -n "$TARGET" ]] && log_info "Target: ${BOLD}$TARGET${RESET} (single-component mode)"

count=$(count_enabled)
if [[ "$count" -eq 0 ]]; then
  log_warn "No enabled components found — nothing to remove."
  exit 0
fi

# Reverse topological order for clean teardown
ordered_indices=$(topo_sort_indices | tac)

removed=0

for idx in $ordered_indices; do
  name=$(enabled_field "$idx" name)
  namespace=$(enabled_field "$idx" namespace)

  [[ -n "$TARGET" && "$name" != "$TARGET" ]] && continue

  if helm status "$name" -n "$namespace" &>/dev/null; then
    log_info "Uninstalling: ${BOLD}$name${RESET} (ns: $namespace)..."
    helm uninstall "$name" -n "$namespace"
    log_ok "  ✓ $name removed"
    removed=$(( removed + 1 ))
  else
    log_info "  $name — not installed, skipping."
  fi

  # Clean up pre-install manifests (best-effort, reverse order)
  while IFS= read -r manifest; do
    [[ -z "$manifest" || "$manifest" == "null" ]] && continue
    local_path="${REPO_ROOT}/${manifest}"
    [[ -f "$local_path" ]] && kubectl delete -f "$local_path" -n "$namespace" --ignore-not-found || true
  done < <(enabled_manifests "$idx")
done

echo ""
log_ok "Done. $removed helm release(s) removed."