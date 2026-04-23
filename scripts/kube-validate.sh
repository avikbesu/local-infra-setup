#!/usr/bin/env bash
# =============================================================================
# scripts/kube-validate.sh
# Pre-flight validation for cluster/helm-components.yaml.
# No running cluster required for static checks.
#
# Exit code 0 = all checks passed.
# Exit code 1 = one or more errors (printed to stderr via log_error).
#
# Usage:
#   ./scripts/kube-validate.sh            # static checks only
#   ./scripts/kube-validate.sh --render   # + helm template dry-run (needs repos)
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/lib/kube-common.sh"

require_yq
require_helm

RENDER=false
[[ "${1:-}" == "--render" ]] && RENDER=true

errors=0
warnings=0

fail()  { log_error "$*"; errors=$(( errors + 1 )); }
warn()  { log_warn  "$*"; warnings=$(( warnings + 1 )); }

log_step "Helm Components Validation"
log_info "Config: $HELM_COMPONENTS_CONFIG"
echo ""

# ── 1. YAML parse ─────────────────────────────────────────────────────────────
log_info "1/5  YAML syntax..."
if ! yq '.' "$HELM_COMPONENTS_CONFIG" > /dev/null 2>&1; then
  fail "YAML parse error in $HELM_COMPONENTS_CONFIG"
  exit 1
fi
log_ok "     YAML syntax OK"

# ── 2. Required fields + file references ──────────────────────────────────────
REQUIRED_FIELDS=(name chart helm_repo helm_repo_url namespace values_file wait_timeout)
total=$(yq '.components | length' "$HELM_COMPONENTS_CONFIG")

log_info "2/5  Required fields ($total component(s))..."

for i in $(seq 0 $(( total - 1 ))); do
  cname=$(yq ".components[$i].name" "$HELM_COMPONENTS_CONFIG")
  enabled=$(yq ".components[$i].enabled" "$HELM_COMPONENTS_CONFIG")

  for field in "${REQUIRED_FIELDS[@]}"; do
    val=$(yq ".components[$i].${field}" "$HELM_COMPONENTS_CONFIG")
    if [[ "$val" == "null" || -z "$val" ]]; then
      fail "Component '$cname': missing required field '$field'"
    fi
  done

  # enabled must be an explicit boolean
  if [[ "$enabled" != "true" && "$enabled" != "false" ]]; then
    fail "Component '$cname': 'enabled' must be true or false, got: '$enabled'"
  fi
done

[[ $errors -eq 0 ]] && log_ok "     All required fields present"

# ── 3. File reference checks ───────────────────────────────────────────────────
log_info "3/5  File references..."

for i in $(seq 0 $(( total - 1 ))); do
  cname=$(yq ".components[$i].name" "$HELM_COMPONENTS_CONFIG")
  enabled=$(yq ".components[$i].enabled" "$HELM_COMPONENTS_CONFIG")
  values_rel=$(yq ".components[$i].values_file" "$HELM_COMPONENTS_CONFIG")
  values_abs="${REPO_ROOT}/${values_rel}"

  if [[ ! -f "$values_abs" ]]; then
    if [[ "$enabled" == "true" ]]; then
      fail "Component '$cname' (enabled): values_file not found: $values_rel"
    else
      warn "Component '$cname' (disabled): values_file not found: $values_rel"
    fi
  fi

  manifest_count=$(yq ".components[$i].pre_manifests | length" "$HELM_COMPONENTS_CONFIG")
  for m in $(seq 0 $(( manifest_count - 1 ))); do
    mrel=$(yq ".components[$i].pre_manifests[$m]" "$HELM_COMPONENTS_CONFIG")
    mabs="${REPO_ROOT}/${mrel}"
    if [[ ! -f "$mabs" ]]; then
      if [[ "$enabled" == "true" ]]; then
        fail "Component '$cname' (enabled): pre_manifest not found: $mrel"
      else
        warn "Component '$cname' (disabled): pre_manifest not found: $mrel"
      fi
    fi
  done
done

[[ $errors -eq 0 ]] && log_ok "     File references OK"

# ── 4. Dependency cycle check ─────────────────────────────────────────────────
log_info "4/5  Dependency cycles..."
if topo_sort_indices > /dev/null 2>&1; then
  log_ok "     No cycles detected"
else
  fail "Circular dependency detected in $HELM_COMPONENTS_CONFIG"
fi

# ── 5. Helm template dry-run (optional) ───────────────────────────────────────
if $RENDER; then
  log_info "5/5  Helm template dry-run (enabled components)..."
  count=$(count_enabled)

  if [[ "$count" -eq 0 ]]; then
    log_warn "     No enabled components — skipping render."
  else
    for i in $(seq 0 $(( count - 1 ))); do
      name=$(enabled_field "$i" name)
      chart=$(enabled_field "$i" chart)
      namespace=$(enabled_field "$i" namespace)
      values_rel=$(enabled_field "$i" values_file)
      values_abs="${REPO_ROOT}/${values_rel}"

      log_info "     Rendering: $name ($chart)..."

      if [[ ! -f "$values_abs" ]]; then
        log_warn "     Skipping '$name': values_file missing (already reported above)"
        continue
      fi

      render_out=$(helm template "$name" "$chart" \
        --namespace "$namespace" \
        --values "$values_abs" 2>&1) && rc=0 || rc=$?

      if [[ $rc -eq 0 ]]; then
        log_ok "     $name: template OK"
      else
        fail "Component '$name': helm template failed"
        echo "$render_out" | head -30 >&2
      fi
    done
  fi
else
  log_info "5/5  Helm template dry-run skipped (pass --render to enable)"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
if [[ $warnings -gt 0 ]]; then
  log_warn "$warnings warning(s) — review disabled components above."
fi

if [[ $errors -gt 0 ]]; then
  log_error "Validation FAILED — $errors error(s). Fix the issues above before deploying."
  exit 1
fi

log_ok "Validation passed (${total} component(s) checked, ${warnings} warning(s))."
