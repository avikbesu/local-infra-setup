#!/usr/bin/env bash
# =============================================================================
# scripts/kube-helm-repos.sh
# Reads cluster/helm-components.yaml and ensures all Helm repos for
# enabled components are registered and up to date.
#
# Usage:  ./scripts/kube-helm-repos.sh [--update-only]
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/lib/kube-common.sh"

require_yq
require_helm

UPDATE_ONLY=false
[[ "${1:-}" == "--update-only" ]] && UPDATE_ONLY=true

log_step "Helm Repo Sync"
log_info "Config: $HELM_COMPONENTS_CONFIG"

count=$(count_enabled)
if [[ "$count" -eq 0 ]]; then
  log_warn "No enabled components found in config — nothing to do."
  exit 0
fi

# Collect unique repos from enabled components
declare -A seen_repos=()

for i in $(seq 0 $((count - 1))); do
  alias=$(enabled_field "$i" helm_repo)
  url=$(enabled_field "$i" helm_repo_url)

  # Skip null entries (component has no helm_repo, e.g. local charts)
  [[ "$alias" == "null" || -z "$alias" ]] && continue

  if [[ -z "${seen_repos[$alias]+_}" ]]; then
    seen_repos[$alias]="$url"
    if $UPDATE_ONLY; then
      log_info "Skip add (--update-only): $alias"
    else
      if helm repo list 2>/dev/null | awk '{print $1}' | grep -qx "$alias"; then
        log_info "Repo already registered: ${BOLD}$alias${RESET} → $url"
      else
        log_info "Adding repo: ${BOLD}$alias${RESET} → $url"
        helm repo add "$alias" "$url"
        log_ok "Added: $alias"
      fi
    fi
  fi
done

if [[ ${#seen_repos[@]} -gt 0 ]]; then
  log_info "Updating helm repos..."
  helm repo update
  log_ok "Helm repos are up to date."
else
  log_warn "No helm repos found in enabled components."
fi