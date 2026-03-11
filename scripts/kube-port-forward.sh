#!/usr/bin/env bash
# =============================================================================
# scripts/kube-port-forward.sh
# Starts kubectl port-forward for every enabled component that has
# port_forward entries defined in cluster/helm-components.yaml.
#
# Usage:
#   ./scripts/kube-port-forward.sh          # start all port-forwards
#   ./scripts/kube-port-forward.sh stop     # kill all active port-forwards
#   ./scripts/kube-port-forward.sh status   # list active port-forwards
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/lib/kube-common.sh"

require_yq
require_kubectl

MODE="${1:-start}"

# ── Stop ──────────────────────────────────────────────────────────────────────
if [[ "$MODE" == "stop" ]]; then
  log_step "Stopping Port-Forwards"
  pids=$(pgrep -f "kubectl port-forward" 2>/dev/null || true)
  if [[ -z "$pids" ]]; then
    log_info "No active kubectl port-forward processes."
  else
    echo "$pids" | xargs kill
    log_ok "Stopped $(echo "$pids" | wc -l | tr -d ' ') port-forward process(es)."
  fi
  exit 0
fi

# ── Status ────────────────────────────────────────────────────────────────────
if [[ "$MODE" == "status" ]]; then
  log_step "Active Port-Forwards"
  pgrep -a "kubectl port-forward" 2>/dev/null \
    | awk '{$1=""; print "  PID " NR ":" $0}' \
    || log_info "No active kubectl port-forward processes."
  exit 0
fi

# ── Start ─────────────────────────────────────────────────────────────────────
log_step "Starting Port-Forwards"
log_info "Config: $HELM_COMPONENTS_CONFIG"

count=$(count_enabled)
started=0

for i in $(seq 0 $((count - 1))); do
  name=$(enabled_field "$i" name)
  namespace=$(enabled_field "$i" namespace)

  # Read port_forward entries: "service:local:remote" per line
  while IFS= read -r entry; do
    [[ -z "$entry" || "$entry" == "null" ]] && continue

    svc=$(echo "$entry" | cut -d: -f1)
    local_port=$(echo "$entry" | cut -d: -f2)
    remote_port=$(echo "$entry" | cut -d: -f3)

    log_info "  $name → svc/$svc  ${local_port}:${remote_port}  (ns: $namespace)"
    kubectl port-forward "svc/${svc}" "${local_port}:${remote_port}" \
      -n "$namespace" &>/dev/null &
    local_pid=$!
    log_ok "  Started (PID $local_pid) → http://localhost:${local_port}"
    ((started++))

  done < <(component_port_forwards "$name")
done

echo ""
if [[ "$started" -eq 0 ]]; then
  log_warn "No port_forward entries found in enabled components."
else
  log_ok "$started port-forward(s) running in background."
  log_info "Run:  make kube-port-forward-stop  to kill all port-forwards."
fi