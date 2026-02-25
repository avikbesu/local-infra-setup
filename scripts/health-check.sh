#!/usr/bin/env bash
set -euo pipefail

COMPOSE_BASE="docker-compose.yml"
COMPOSE_OVERRIDE="docker-compose.override.yml"
DC="docker compose -f $COMPOSE_BASE -f $COMPOSE_OVERRIDE"

SERVICES=$($DC ps --services 2>/dev/null)
ALL_HEALTHY=true

echo "🔍 Checking service health..."
echo ""

for svc in $SERVICES; do
  STATUS=$($DC ps "$svc" --format json 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('Health','unknown'))" 2>/dev/null \
    || echo "no-healthcheck")
  
  if [[ "$STATUS" == "healthy" ]]; then
    echo "  ✅ $svc → $STATUS"
  elif [[ "$STATUS" == "no-healthcheck" ]]; then
    echo "  ⚪ $svc → $STATUS (skipped)"
  else
    echo "  ❌ $svc → $STATUS"
    ALL_HEALTHY=false
  fi
done

echo ""
$ALL_HEALTHY && echo "✅ All services healthy" || { echo "❌ Some services are unhealthy"; exit 1; }