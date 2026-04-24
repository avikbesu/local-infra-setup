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
CLUSTER_NAME="${KIND_CLUSTER_NAME:-local-cluster}"
CTX="kind-${CLUSTER_NAME}"

log_step "Kube Health Check"
[[ -n "$TARGET" ]] && log_info "Component: ${BOLD}$TARGET${RESET}" || log_info "Scope: all enabled components"
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

    # Get pods for this release (label: app.kubernetes.io/instance=<name>)
    pod_list=$(kubectl get pods -n "$ns" \
      -l "app.kubernetes.io/instance=${name}" \
      --context "$CTX" \
      --no-headers \
      --output=custom-columns='NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready' \
      2>/dev/null || true)

    if [[ -z "$pod_list" ]]; then
      # No pods yet — still starting
      log_info "  $name ($ns): no pods yet..."
      all_ok=false
      continue
    fi

    while IFS= read -r line; do
      pod_name=$(echo "$line" | awk '{print $1}')
      phase=$(echo "$line" | awk '{print $2}')
      ready=$(echo "$line" | awk '{print $3}')

      if [[ "$phase" != "Running" || "$ready" != "true" ]]; then
        log_info "  $name/$pod_name ($ns): $phase / ready=$ready — waiting..."
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
exit_code=0

for name in "${!NS_MAP[@]}"; do
  ns="${NS_MAP[$name]}"

  pod_list=$(kubectl get pods -n "$ns" \
    -l "app.kubernetes.io/instance=${name}" \
    --context "$CTX" \
    --no-headers \
    --output=custom-columns='NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,RESTARTS:.status.containerStatuses[0].restartCount' \
    2>/dev/null || true)

  if [[ -z "$pod_list" ]]; then
    echo -e "  ${RED}❌${RESET} $name ($ns): no pods found"
    exit_code=1
    continue
  fi

  comp_ok=true
  while IFS= read -r line; do
    pod_name=$(echo "$line" | awk '{print $1}')
    phase=$(echo "$line"    | awk '{print $2}')
    ready=$(echo "$line"    | awk '{print $3}')
    restarts=$(echo "$line" | awk '{print $4}')

    if [[ "$phase" == "Running" && "$ready" == "true" ]]; then
      echo -e "  ${GREEN}✅${RESET} $name/$pod_name ($ns): Running/Ready  restarts=${restarts}"
    else
      echo -e "  ${RED}❌${RESET} $name/$pod_name ($ns): phase=$phase ready=$ready restarts=${restarts}"
      comp_ok=false
      exit_code=1

      # Surface recent events for failing pods
      echo -e "     ${YELLOW}Events:${RESET}"
      kubectl describe pod "$pod_name" -n "$ns" --context "$CTX" 2>/dev/null \
        | awk '/^Events:/,0' | tail -10 | sed 's/^/       /'

      # Surface error lines from logs
      recent_errors=$(kubectl logs "$pod_name" -n "$ns" --context "$CTX" --tail=30 2>/dev/null \
        | grep -iE "error|exception|fatal|failed" | tail -5 || true)
      if [[ -n "$recent_errors" ]]; then
        echo -e "     ${YELLOW}Log errors:${RESET}"
        echo "$recent_errors" | sed 's/^/       /'
      fi
    fi
  done <<< "$pod_list"
done

echo ""
if [[ $exit_code -eq 0 ]]; then
  log_ok "All pods healthy."
else
  log_error "One or more pods are not healthy."
  log_info "  Full status:    make kube-status"
  log_info "  Detailed logs:  make kube-logs COMPONENT=<name>"
  log_info "  Redeploy:       make kube-remove-one COMPONENT=<name> && make kube-deploy-one COMPONENT=<name>"
fi

exit $exit_code
