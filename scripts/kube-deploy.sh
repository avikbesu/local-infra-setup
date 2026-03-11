#!/usr/bin/env bash
# =============================================================================
# scripts/kube-deploy.sh
# Deploys all enabled helm components from cluster/helm-components.yaml in
# topologically-sorted dependency order.
#
# Usage:
#   ./scripts/kube-deploy.sh              # deploy all enabled components
#   ./scripts/kube-deploy.sh <name>       # deploy a single named component only
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/lib/kube-common.sh"

require_yq
require_helm
require_kubectl

TARGET="${1:-}"    # optional: deploy only this named component

log_step "Kube Deploy"
log_info "Config:  $HELM_COMPONENTS_CONFIG"
[[ -n "$TARGET" ]] && log_info "Target:  ${BOLD}$TARGET${RESET} (single-component mode)"

count=$(count_enabled)
if [[ "$count" -eq 0 ]]; then
  log_warn "No enabled components found in config — nothing to deploy."
  exit 0
fi

# ── Validate target if specified ─────────────────────────────────────────────
if [[ -n "$TARGET" ]]; then
  found=false
  for i in $(seq 0 $((count - 1))); do
    [[ "$(enabled_field "$i" name)" == "$TARGET" ]] && found=true && break
  done
  $found || die "Component '${TARGET}' not found or not enabled in config."
fi

# ── Resolve deployment order via topological sort ────────────────────────────
log_info "Resolving deployment order..."
ordered_indices=$(topo_sort_indices)

deployed=()

# ── Deploy loop ───────────────────────────────────────────────────────────────
for idx in $ordered_indices; do
  name=$(enabled_field "$idx" name)

  # Single-component mode: skip everything except the target
  if [[ -n "$TARGET" && "$name" != "$TARGET" ]]; then
    deployed+=("$name")
    continue
  fi

  chart=$(enabled_field "$idx" chart)
  namespace=$(enabled_field "$idx" namespace)
  values_file="${REPO_ROOT}/$(enabled_field "$idx" values_file)"
  wait_timeout=$(enabled_field "$idx" wait_timeout)

  log_step "Deploying: $name"
  log_info "  Chart:     $chart"
  log_info "  Namespace: $namespace"
  log_info "  Values:    $values_file"
  log_info "  Timeout:   $wait_timeout"

  # Ensure namespace exists
  kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -

  # Apply any pre-install manifests
  while IFS= read -r manifest; do
    [[ -z "$manifest" || "$manifest" == "null" ]] && continue
    local_path="${REPO_ROOT}/${manifest}"
    if [[ -f "$local_path" ]]; then
      log_info "  Applying manifest: $manifest"
      kubectl apply -f "$local_path" -n "$namespace"
    else
      log_warn "  Manifest not found, skipping: $local_path"
    fi
  done < <(enabled_manifests "$idx")

  # Validate values file
  if [[ ! -f "$values_file" ]]; then
    die "Values file not found: $values_file"
  fi

  # Helm upgrade --install
  log_info "  Running helm upgrade --install..."
  helm upgrade --install "$name" "$chart" \
    --namespace "$namespace" \
    --values "$values_file" \
    --wait \
    --timeout "$wait_timeout"

  log_ok "✓ $name deployed"
  deployed+=("$name")
done

echo ""
log_ok "Deployment complete. ${#deployed[@]} component(s) processed."
log_info "  Run: make kube-status        → check pod health"
log_info "  Run: make kube-port-forward  → expose services locally"