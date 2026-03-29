#!/usr/bin/env bash
# ============================================================
# scripts/gen-secrets.sh
#
# Thin bash orchestrator for secret generation.
# Responsibilities:
#   1. Verify python3 is available
#   2. Create/reuse an isolated .venv-secrets virtualenv
#   3. Ensure pyyaml + cryptography are installed in the venv
#   4. Resolve paths and forward to scripts/gen_secrets.py
#
# All parsing, validation, generation, and writing logic lives
# in scripts/gen_secrets.py — edit that file to change behaviour.
#
# Usage:
#   bash scripts/gen-secrets.sh                          # generate missing secrets
#   bash scripts/gen-secrets.sh --rotate KEY1,KEY2       # rotate specific keys
#   make secrets                                          # via Makefile
#   make rotate KEYS=KEY1,KEY2                            # rotation via Makefile
#
# Environment overrides:
#   SECRETS_CONFIG=config/secrets.yaml           # default
#   ENV_LOCAL=.env.local                         # default
#   VENV_DIR=.venv-secrets                       # default
#
# CHANGE [6]: Replaced ad-hoc `pip install --user` with an isolated
# project-local venv (.venv-secrets). Benefits:
#   - Never mutates the system or user Python environment
#   - Reproducible: same packages every run, no version drift
#   - CI-safe: works on externally-managed Python (Ubuntu 23+, Debian 12+)
#   - cryptography is now installed here as a hard dependency,
#     removing the silent fernet fallback (see gen_secrets.py CHANGE [9])
# ============================================================
set -euo pipefail

# ── Resolve paths ────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SECRETS_CONFIG="${SECRETS_CONFIG:-${REPO_ROOT}/config/secrets.yaml}"
ENV_LOCAL="${ENV_LOCAL:-${REPO_ROOT}/.env.local}"
PY_SCRIPT="${SCRIPT_DIR}/gen_secrets.py"

# CHANGE [6]: Venv lives at repo root, git-ignored via .gitignore entry.
VENV_DIR="${REPO_ROOT}/${VENV_DIR:-.venv-secrets}"
VENV_PYTHON="${VENV_DIR}/bin/python"
VENV_PIP="${VENV_DIR}/bin/pip"

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

# ── Isolated venv bootstrap ──────────────────────────────────
# CHANGE [6]: Create venv on first run; skip creation on subsequent runs.
# The sentinel check uses the python binary, not just the directory,
# so a partial/broken venv is detected and recreated.
if [[ ! -x "${VENV_PYTHON}" ]]; then
  echo "📦  Creating isolated secret-gen venv at ${VENV_DIR} ..."
  python3 -m venv "${VENV_DIR}"
  echo "    ✔  Venv created."
fi

# CHANGE [9]: cryptography is a hard dependency — no silent fallback.
# Install/upgrade quietly; only prints on actual installation.
REQUIRED_PKGS=(pyyaml cryptography)
MISSING_PKGS=()

for pkg in "${REQUIRED_PKGS[@]}"; do
  if ! "${VENV_PYTHON}" -c "import ${pkg//-/_}" &>/dev/null; then
    MISSING_PKGS+=("$pkg")
  fi
done

if [[ ${#MISSING_PKGS[@]} -gt 0 ]]; then
  echo "📦  Installing missing packages into venv: ${MISSING_PKGS[*]} ..."
  "${VENV_PIP}" install --quiet --upgrade "${MISSING_PKGS[@]}"
  echo "    ✔  Packages installed."
fi

# ── Delegate to Python ───────────────────────────────────────
exec "${VENV_PYTHON}" "$PY_SCRIPT" \
  --config   "$SECRETS_CONFIG" \
  --env-file "$ENV_LOCAL" \
  "$@"   # forward any extra flags (e.g. --rotate) transparently