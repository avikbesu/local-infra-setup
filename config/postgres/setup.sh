#!/usr/bin/env bash
set -euo pipefail

for f in /opt/init/sql/*.sql; do
  [ -f "$f" ] || continue
  echo "▶  running $f"
  psql -h postgres -U "${POSTGRES_USER}" -f "$f"
  echo "✔  $f done"
done
echo "postgres-init complete."
