#!/usr/bin/env bash
# =============================================================================
# scripts/lib/kube-common.sh
# Shared utilities sourced by every kube-*.sh script.
# Source with:  source "$(dirname "$0")/lib/kube-common.sh"
# =============================================================================

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log_info()  { echo -e "${CYAN}[INFO]${RESET}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${RESET}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
log_error() { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
log_step()  { echo -e "\n${BOLD}── $* ──${RESET}"; }

die() { log_error "$*"; exit 1; }

# ── Repo-root resolution ─────────────────────────────────────────────────────
# Works when called from anywhere; walks up until makefile is found.
repo_root() {
  local dir="${BASH_SOURCE[1]}"
  dir="$(cd "$(dirname "$dir")" && pwd)"
  while [[ "$dir" != "/" ]]; do
    [[ -f "$dir/makefile" || -f "$dir/Makefile" ]] && { echo "$dir"; return; }
    dir="$(dirname "$dir")"
  done
  die "Cannot locate repo root (no makefile found)"
}

# ── Config file ───────────────────────────────────────────────────────────────
REPO_ROOT="$(repo_root)"
HELM_COMPONENTS_CONFIG="${HELM_COMPONENTS_CONFIG:-${REPO_ROOT}/cluster/helm-components.yaml}"

# ── Tool guards ───────────────────────────────────────────────────────────────
require_tool() {
  local tool="$1" hint="${2:-}"
  command -v "$tool" &>/dev/null || die "'$tool' not found.${hint:+ Install: $hint}"
}

require_yq() {
  require_tool yq "https://github.com/mikefarah/yq/releases  or  brew install yq  or  snap install yq"
  # Ensure mikefarah/yq (v4), not python-yq (different syntax)
  local ver
  ver=$(yq --version 2>&1)
  [[ "$ver" == *"mikefarah"* || "$ver" == *"(https://github.com/mikefarah/yq)"* || "$ver" =~ v4\. ]] \
    || die "yq v4 (mikefarah) is required. Found: $ver"
}

require_helm()    { require_tool helm    "https://helm.sh/docs/intro/install/"; }
require_kubectl() { require_tool kubectl "https://kubernetes.io/docs/tasks/tools/"; }
require_kind()    { require_tool kind    "https://kind.sigs.k8s.io/docs/user/quick-start/#installation"; }

# ── YQ helpers ────────────────────────────────────────────────────────────────
# Count enabled components
count_enabled() {
  yq '[.components[] | select(.enabled == true)] | length' "$HELM_COMPONENTS_CONFIG"
}

# Field value for the i-th enabled component (0-based)
# Usage: enabled_field <index> <field>
enabled_field() {
  local idx="$1" field="$2"
  yq "[.components[] | select(.enabled == true)][$idx].${field}" "$HELM_COMPONENTS_CONFIG"
}

# All values of a field across enabled components (newline-separated)
# Usage: all_enabled_field <field>
all_enabled_field() {
  yq '.components[] | select(.enabled == true) | .'"$1" "$HELM_COMPONENTS_CONFIG"
}

# depends_on list for the i-th enabled component
# Usage: enabled_deps <index>  → space-separated names
enabled_deps() {
  local idx="$1"
  yq "[.components[] | select(.enabled == true)][$idx].depends_on[]" \
    "$HELM_COMPONENTS_CONFIG" 2>/dev/null | tr '\n' ' '
}

# pre_manifests list for the i-th enabled component
# Usage: enabled_manifests <index>  → newline-separated paths
enabled_manifests() {
  local idx="$1"
  yq "[.components[] | select(.enabled == true)][$idx].pre_manifests[]" \
    "$HELM_COMPONENTS_CONFIG" 2>/dev/null
}

# port_forward entries for a named component
# Usage: component_port_forwards <name>  → lines of "service:local:remote"
component_port_forwards() {
  local name="$1"
  yq ".components[] | select(.name == \"$name\" and .enabled == true) \
      | .port_forward[] | .service + \":\" + (.local_port | tostring) + \":\" + (.remote_port | tostring)" \
    "$HELM_COMPONENTS_CONFIG" 2>/dev/null
}

# ── Topological sort ──────────────────────────────────────────────────────────
# Writes an ordered list of component *indices* (into the enabled array) to stdout.
# Uses Kahn's algorithm; exits non-zero on cycle detection.
topo_sort_indices() {
  require_yq
  local count
  count=$(count_enabled)
  local -a names=() deps=()
  local i

  # Build name array and deps array
  for i in $(seq 0 $((count - 1))); do
    names[$i]=$(enabled_field "$i" name)
    deps[$i]=$(enabled_deps "$i")
  done

  # in_degree[i] = number of unresolved deps for component i
  local -a in_degree=()
  for i in $(seq 0 $((count - 1))); do
    local d=0
    for dep in ${deps[$i]}; do
      # Only count deps that are also in the enabled set
      for j in $(seq 0 $((count - 1))); do
        [[ "${names[$j]}" == "$dep" ]] && ((d++)) && break
      done
    done
    in_degree[$i]=$d
  done

  local -a queue=() result=()
  for i in $(seq 0 $((count - 1))); do
    [[ "${in_degree[$i]}" -eq 0 ]] && queue+=("$i")
  done

  while [[ ${#queue[@]} -gt 0 ]]; do
    local cur="${queue[0]}"
    queue=("${queue[@]:1}")
    result+=("$cur")
    # For every component whose dependency is cur, reduce in_degree
    for i in $(seq 0 $((count - 1))); do
      for dep in ${deps[$i]}; do
        if [[ "$dep" == "${names[$cur]}" ]]; then
          ((in_degree[$i]--))
          [[ "${in_degree[$i]}" -eq 0 ]] && queue+=("$i")
        fi
      done
    done
  done

  if [[ ${#result[@]} -ne $count ]]; then
    die "Circular dependency detected in helm-components.yaml"
  fi

  printf '%s\n' "${result[@]}"
}