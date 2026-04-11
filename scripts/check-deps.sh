#!/usr/bin/env bash
# =============================================================================
# scripts/check-deps.sh
# Checks (and optionally installs) required CLI tools.
#
# Usage:
#   ./scripts/check-deps.sh            # check only
#   ./scripts/check-deps.sh --install  # check and install missing tools
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/lib/kube-common.sh"

INSTALL_MISSING=false
[[ "${1:-}" == "--install" ]] && INSTALL_MISSING=true

# ── Install helpers ───────────────────────────────────────────────────────────
install_kubectl() {
  log_info "Installing kubectl..."
  local stable
  stable=$(curl -sL https://dl.k8s.io/release/stable.txt)
  curl -sLo /tmp/kubectl "https://dl.k8s.io/release/${stable}/bin/linux/amd64/kubectl"
  chmod +x /tmp/kubectl && sudo mv /tmp/kubectl /usr/local/bin/kubectl
}

install_kind() {
  log_info "Installing kind..."
  local ver
  ver=$(curl -sL https://api.github.com/repos/kubernetes-sigs/kind/releases/latest | grep tag_name | cut -d'"' -f4)
  curl -sLo /tmp/kind "https://kind.sigs.k8s.io/dl/${ver}/kind-linux-amd64"
  chmod +x /tmp/kind && sudo mv /tmp/kind /usr/local/bin/kind
}

install_helm() {
  log_info "Installing helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
}

install_yq() {
  log_info "Installing yq (mikefarah)..."
  local ver
  ver=$(curl -sL https://api.github.com/repos/mikefarah/yq/releases/latest | grep tag_name | cut -d'"' -f4)
  curl -sLo /tmp/yq "https://github.com/mikefarah/yq/releases/download/${ver}/yq_linux_amd64"
  chmod +x /tmp/yq && sudo mv /tmp/yq /usr/local/bin/yq
}

install_gh() {
  log_info "Installing gh (GitHub CLI)..."
  local out
  out=$(mktemp)
  (type -p wget >/dev/null || (sudo apt-get update -q && sudo apt-get install -y wget))
  sudo mkdir -p -m 755 /etc/apt/keyrings
  wget -nv -O"$out" https://cli.github.com/packages/githubcli-archive-keyring.gpg
  cat "$out" | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
  sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  sudo mkdir -p -m 755 /etc/apt/sources.list.d
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
  sudo apt-get update -q && sudo apt-get install -y gh
}

# ── Check function ─────────────────────────────────────────────────────────────
check_tool() {
  local tool="$1"
  local install_fn="${2:-}"

  if command -v "$tool" &>/dev/null; then
    local ver
    ver=$("$tool" version --short 2>/dev/null || "$tool" --version 2>/dev/null | head -1 || echo "installed")
    log_ok "  $tool — $ver"
    return 0
  fi

  log_warn "  $tool — NOT FOUND"
  if $INSTALL_MISSING && [[ -n "$install_fn" ]]; then
    $install_fn
    log_ok "  $tool — installed"
  fi
}

log_step "Dependency Check"
echo ""
check_tool docker
check_tool kubectl    install_kubectl
check_tool kind       install_kind
check_tool helm       install_helm
check_tool yq         install_yq
check_tool gh         install_gh
echo ""

if $INSTALL_MISSING; then
  log_ok "All tools installed."
else
  log_info "Tip: run with --install to auto-install missing tools."
fi