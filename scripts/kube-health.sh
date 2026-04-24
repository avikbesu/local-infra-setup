#!/usr/bin/env bash
# =============================================================================
# scripts/kube-health.sh
# Polls pod readiness for all enabled components (or a single named component)
# until all pods are Running+Ready or a timeout is reached.
# Exits 0 when all pods are healthy, 1 if any pod is unhealthy after timeout.
#
# Usage:
#   ./scripts/kube-health.sh              # check all enabled components
#   ./scripts/kube-health.sh <name>       # check a single component
#
# Environment:
#   KUBE_HEALTH_TIMEOUT  — seconds to wait (default: 300)
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/lib/kube-common.sh"

require_yq
require_kubectl

TARGET="${1:-}"
TIMEOUT="${KUBE_HEALTH_TIMEOUT:-300}"
CTX=$(get_kind_context)

log_step "Kube Health Check"
[[ -n "$TARGET" ]] \
  && log_info "Component: ${BOLD}$TARGET${RESET}" \
  || log_info "Scope:     all enabled components"
log_info "Timeout:   ${TIMEOUT}s"

# ── Collect namespaces to check ───────────────────────────────────────────────
declare -A NS_MAP   # component → namespace
count=$(count_enabled)
for i in $(seq 0 $((count - 1))); do
  name=$(enabled_field "$i" name)
  ns=$(enabled_field "$i" namespace)
  [[ -z "$TARGET" || "$name" == "$TARGET" ]] && NS_MAP["$name"]="$ns"
done

if [[ ${#NS_MAP[@]} -eq 0 ]]; then
  log_warn "No matching enabled component(s) found."
  exit 0
fi

# ── Poll until all pods are ready ─────────────────────────────────────────────
DEADLINE=$(( $(date +%s) + TIMEOUT ))
ALL_READY=false

while [[ $(date +%s) -lt $DEADLINE ]]; do
  all_ok=true

  for name in "${!NS_MAP[@]}"; do
    ns="${NS_MAP[$name]}"
    pod_list=$(list_component_pods "$name" "$ns")

    if [[ -z "$pod_list" ]]; then
      log_info "  $name ($ns): no pods yet..."
      all_ok=false
      continue
    fi

    while IFS= read -r line; do
      local_phase=$(awk '{print $2}' <<< "$line")
      local_ready=$(awk '{print $3}' <<< "$line")
      if [[ "$local_phase" != "Running" || "$local_ready" != "true" ]]; then
        log_info "  $name/$(awk '{print $1}' <<< "$line") ($ns): $local_phase / ready=$local_ready — waiting..."
        all_ok=false
      fi
    done <<< "$pod_list"
  done

  if $all_ok; then
    ALL_READY=true
    break
  fi

  sleep 5
done

echo ""

# ── Final report ──────────────────────────────────────────────────────────────
EXIT_CODE=0
COLS_WITH_RESTARTS="NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,RESTARTS:.status.containerStatuses[0].restartCount"

for name in "${!NS_MAP[@]}"; do
  ns="${NS_MAP[$name]}"
  pod_list=$(list_component_pods "$name" "$ns" "$COLS_WITH_RESTARTS")

  if [[ -z "$pod_list" ]]; then
    printf '  %b❌%b %s (%s): no pods found\n' "$RED" "$RESET" "$name" "$ns"
    EXIT_CODE=1
    continue
  fi

  while IFS= read -r line; do
    pod_name=$(awk '{print $1}' <<< "$line")
    phase=$(awk '{print $2}'    <<< "$line")
    ready=$(awk '{print $3}'    <<< "$line")
    restarts=$(awk '{print $4}' <<< "$line")

    if [[ "$phase" == "Running" && "$ready" == "true" ]]; then
      printf '  %b✅%b %s/%s (%s): Running/Ready  restarts=%s\n' \
        "$GREEN" "$RESET" "$name" "$pod_name" "$ns" "$restarts"
    else
      printf '  %b❌%b %s/%s (%s): phase=%s ready=%s restarts=%s\n' \
        "$RED" "$RESET" "$name" "$pod_name" "$ns" "$phase" "$ready" "$restarts"
      EXIT_CODE=1

      printf '     %bEvents:%b\n' "$YELLOW" "$RESET"
      kubectl describe pod "$pod_name" -n "$ns" --context "$CTX" 2>/dev/null \
        | awk '/^Events:/,0' | tail -10 | sed 's/^/       /'

      local_errors=$(kubectl logs "$pod_name" -n "$ns" --context "$CTX" --tail=30 2>/dev/null \
        | grep -iE "error|exception|fatal|failed" | tail -5 || true)
      if [[ -n "$local_errors" ]]; then
        printf '     %bLog errors:%b\n' "$YELLOW" "$RESET"
        echo "$local_errors" | sed 's/^/       /'
      fi
    fi
  done <<< "$pod_list"
done

echo ""
if [[ $EXIT_CODE -eq 0 ]]; then
  log_ok "All pods healthy."
else
  log_error "One or more pods are not healthy."
  log_info "  Full status:    make kube-status"
  log_info "  Detailed logs:  make kube-logs COMPONENT=<name>"
  log_info "  Redeploy:       make kube-remove-one COMPONENT=<name> && make kube-deploy-one COMPONENT=<name>"
fi

exit $EXIT_CODE
