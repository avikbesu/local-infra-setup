#!/usr/bin/env bash
# ============================================================
# scripts/gen-secrets.sh
#
# Thin bash orchestrator for secret generation.
# Responsibilities:
#   1. Verify runtime dependencies (python3, pip)
#   2. Ensure PyYAML is installed
#   3. Resolve paths and forward to scripts/gen_secrets.py
#
# All parsing, validation, generation, and writing logic lives
# in scripts/gen_secrets.py — edit that file to change behaviour.
#
# Usage:
#   bash scripts/gen-secrets.sh                  # defaults
#   make secrets                                  # via Makefile
#
# Environment overrides:
#   SECRETS_CONFIG=config/secrets.yaml           # default
#   ENV_LOCAL=.env.local                         # default
# ============================================================
set -euo pipefail

# ── Resolve script directory so the script works from any CWD ─
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ── Paths (overridable via env, resolved relative to repo root) ─
SECRETS_CONFIG="${SECRETS_CONFIG:-${REPO_ROOT}/config/secrets.yaml}"
ENV_LOCAL="${ENV_LOCAL:-${REPO_ROOT}/.env.local}"
PY_SCRIPT="${SCRIPT_DIR}/gen_secrets.py"

# ── Dependency: python3 ──────────────────────────────────────
if ! command -v python3 &>/dev/null; then
  echo "❌  python3 is required but was not found in PATH." >&2
  exit 1
fi

# ── Dependency: gen_secrets.py ───────────────────────────────
if [[ ! -f "$PY_SCRIPT" ]]; then
  echo "❌  Python script not found: $PY_SCRIPT" >&2
  echo "    Ensure scripts/gen_secrets.py exists alongside this script." >&2
  exit 1
fi

# ── Dependency: PyYAML ───────────────────────────────────────
if ! python3 -c "import yaml" &>/dev/null; then
  echo "📦  PyYAML not found — installing..."
  pip3 install --quiet --user pyyaml \
    || pip3 install --quiet pyyaml \
    || {
      echo "❌  Could not install PyYAML. Run: pip3 install pyyaml" >&2
      exit 1
    }
  echo "    ✔  PyYAML installed."
fi

# ── Delegate to Python ───────────────────────────────────────
exec python3 "$PY_SCRIPT" \
  --config  "$SECRETS_CONFIG" \
  --env-file "$ENV_LOCAL"