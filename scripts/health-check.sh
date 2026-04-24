#!/usr/bin/env bash
# =============================================================================
# scripts/health-check.sh
# Reports health status for all running Docker Compose services.
# Exits 0 when all health-checked services are healthy, 1 otherwise.
#
# Usage:  ./scripts/health-check.sh   (or: make health)
# =============================================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

require_tool docker

log_step "Docker Compose Health"

SERVICES=$(docker compose ps --services 2>/dev/null || true)

if [[ -z "$SERVICES" ]]; then
  log_warn "No running services found."
  exit 0
fi

all_healthy=true

while IFS= read -r svc; do
  status=$(docker compose ps "$svc" --format json 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('Health',''))" 2>/dev/null \
    || true)

  case "${status:-}" in
    healthy)
      log_ok "  $svc — healthy" ;;
    "")
      log_info "  $svc — no healthcheck" ;;
    *)
      log_error "  $svc — $status"
      all_healthy=false ;;
  esac
done <<< "$SERVICES"

echo ""
if $all_healthy; then
  log_ok "All health-checked services are healthy."
else
  log_error "One or more services are unhealthy."
  exit 1
fi
