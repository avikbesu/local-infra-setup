#!/usr/bin/env bash
# =============================================================================
# scripts/gen-secrets.sh
# Thin orchestrator for secret generation. Delegates all parsing, validation,
# generation, and writing logic to scripts/gen_secrets.py.
#
# Responsibilities:
#   1. Verify python3 is available
#   2. Create/reuse an isolated .venv-secrets virtualenv
#   3. Ensure pyyaml + cryptography are installed in the venv
#   4. Resolve paths and delegate to gen_secrets.py
#
# Usage:
#   bash scripts/gen-secrets.sh                      # generate missing secrets
#   bash scripts/gen-secrets.sh --rotate KEY1,KEY2   # rotate specific keys
#   make secrets                                      # via Makefile
#   make rotate KEYS=KEY1,KEY2                        # rotation via Makefile
#
# Environment overrides:
#   SECRETS_CONFIG=config/secrets.yaml    (default)
#   ENV_LOCAL=.env.local                  (default)
#   VENV_DIR=.venv-secrets                (default)
# =============================================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

SECRETS_CONFIG="${SECRETS_CONFIG:-${REPO_ROOT}/config/secrets.yaml}"
ENV_LOCAL="${ENV_LOCAL:-${REPO_ROOT}/.env.local}"
PY_SCRIPT="${REPO_ROOT}/scripts/gen_secrets.py"
VENV_DIR="${REPO_ROOT}/${VENV_DIR:-.venv-secrets}"
VENV_PYTHON="${VENV_DIR}/bin/python"
VENV_PIP="${VENV_DIR}/bin/pip"

# ── Pre-flight ────────────────────────────────────────────────────────────────
command -v python3 &>/dev/null || die "python3 is required but was not found in PATH."
[[ -f "$PY_SCRIPT" ]] || die "Python script not found: $PY_SCRIPT"

# ── Isolated venv bootstrap ───────────────────────────────────────────────────
# Create on first run; a missing python binary indicates a partial/broken venv.
if [[ ! -x "${VENV_PYTHON}" ]]; then
  log_info "Creating isolated secret-gen venv at ${VENV_DIR} ..."
  python3 -m venv "${VENV_DIR}"
  log_ok "Venv created."
fi

REQUIRED_PKGS=(pyyaml cryptography)
MISSING_PKGS=()

for pkg in "${REQUIRED_PKGS[@]}"; do
  "${VENV_PYTHON}" -c "import ${pkg//-/_}" &>/dev/null || MISSING_PKGS+=("$pkg")
done

if [[ ${#MISSING_PKGS[@]} -gt 0 ]]; then
  log_info "Installing missing packages into venv: ${MISSING_PKGS[*]} ..."
  "${VENV_PIP}" install --quiet --upgrade "${MISSING_PKGS[@]}"
  log_ok "Packages installed."
fi

# ── Delegate to Python ────────────────────────────────────────────────────────
exec "${VENV_PYTHON}" "$PY_SCRIPT" \
  --config   "$SECRETS_CONFIG" \
  --env-file "$ENV_LOCAL" \
  "$@"
