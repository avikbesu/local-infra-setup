#!/usr/bin/env bash
# =============================================================================
# scripts/lib/common.sh
# General-purpose library: structured logging, error handling, tool validation.
#
# Source with:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
#
# Environment variables (all optional):
#   DEBUG=1          Enable debug log lines and ERR trap with call stack
#   NO_COLOR=1       Force-disable ANSI colours
# =============================================================================

# ── Colour support ─────────────────────────────────────────────────────────────
# Colours are disabled when stderr is not a tty or NO_COLOR is set.
if [[ -t 2 && "${NO_COLOR:-}" != "1" ]]; then
  _CLR_RED='\033[0;31m' _CLR_YELLOW='\033[1;33m' _CLR_GREEN='\033[0;32m'
  _CLR_CYAN='\033[0;36m' _CLR_BOLD='\033[1m' _CLR_RESET='\033[0m'
else
  _CLR_RED='' _CLR_YELLOW='' _CLR_GREEN='' _CLR_CYAN='' _CLR_BOLD='' _CLR_RESET=''
fi

# Export colour variables for use in printf/echo in calling scripts.
RED="$_CLR_RED"; YELLOW="$_CLR_YELLOW"; GREEN="$_CLR_GREEN"
CYAN="$_CLR_CYAN"; BOLD="$_CLR_BOLD"; RESET="$_CLR_RESET"

# ── Logging ─────────────────────────────────────────────────────────────────────
# All log output goes to stderr — stdout is reserved for machine-readable data.
# Format: [YYYY-MM-DDTHH:MM:SSZ] [LEVEL] message
_log() {
  local level="$1" color="$2"; shift 2
  printf '%s [%s] %b%s%b\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$level" "$color" "$*" "$_CLR_RESET" >&2
}

log_info()  { _log "INFO " "$_CLR_CYAN"   "$@"; }
log_ok()    { _log "OK   " "$_CLR_GREEN"  "$@"; }
log_warn()  { _log "WARN " "$_CLR_YELLOW" "$@"; }
log_error() { _log "ERROR" "$_CLR_RED"    "$@"; }
log_debug() { [[ "${DEBUG:-0}" == "1" ]] && _log "DEBUG" "" "$@" || true; }
log_step()  { printf '\n%b── %s ──%b\n' "$_CLR_BOLD" "$*" "$_CLR_RESET" >&2; }

# ── Error handling ─────────────────────────────────────────────────────────────
# die <message> [exit_code=1]
die() {
  log_error "${1:-fatal error}"
  exit "${2:-1}"
}

# Installed as ERR trap when DEBUG=1; prints the failed command and call stack.
_err_handler() {
  local rc=$? lineno="${BASH_LINENO[0]}"
  log_error "Command failed (exit $rc) at line $lineno: $BASH_COMMAND"
  local i
  for (( i=1; i<${#FUNCNAME[@]}; i++ )); do
    log_debug "  #$i  ${FUNCNAME[$i]:-main}  ${BASH_SOURCE[$i]:-}:${BASH_LINENO[$(( i - 1 ))]}"
  done
}
[[ "${DEBUG:-0}" == "1" ]] && trap '_err_handler' ERR

# ── Environment validation ─────────────────────────────────────────────────────
# require_env VAR1 VAR2 ... — asserts all named variables are set and non-empty.
require_env() {
  local missing=()
  for var in "$@"; do
    [[ -z "${!var:-}" ]] && missing+=("$var")
  done
  [[ ${#missing[@]} -eq 0 ]] || die "Required env var(s) not set: ${missing[*]}"
}

# ── Tool validation ────────────────────────────────────────────────────────────
# Functional test: verifies the binary actually executes, not just exists.
# Handles edge cases such as broken snap packages on WSL2 (they exist in PATH
# but fail at runtime with XDG_RUNTIME_DIR errors, exit code 46).
#
# kubectl uses 'version --client' rather than '--version'.
_tool_works() {
  local tool="$1"
  case "$tool" in
    kubectl) "$tool" version --client &>/dev/null ;;
    *)       "$tool" --version &>/dev/null || "$tool" version &>/dev/null ;;
  esac
}

# Short version string for display purposes.
_tool_version() {
  local tool="$1"
  case "$tool" in
    kubectl) "$tool" version --client 2>/dev/null | grep -o 'v[0-9][^"]*' | head -1 ;;
    *)       "$tool" --version 2>/dev/null | head -1 ;;
  esac
}

# require_tool <name> [install_hint]
require_tool() {
  local tool="$1" hint="${2:-}"
  if ! command -v "$tool" &>/dev/null; then
    die "'$tool' not found.${hint:+ Install: $hint}"
  fi
  if ! _tool_works "$tool"; then
    die "'$tool' at $(command -v "$tool") failed to execute (broken install?).${hint:+ Re-install: $hint}"
  fi
}

# ── Repo root ─────────────────────────────────────────────────────────────────
# Derived from this file's own location: scripts/lib/common.sh → ../../
_COMMON_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${_COMMON_LIB_DIR}/../.." && pwd)}"
