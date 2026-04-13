#!/usr/bin/env bash
# PostToolUse hook — runs `make lint` after any edit to a compose file.
# Prints a warning if lint fails, but does not block (async hook).
set -euo pipefail

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [[ -z "$FILE" ]]; then
  exit 0
fi

case "$FILE" in
  *compose/*.yaml|*compose/*.yml)
    REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null || echo ".")"
    cd "$REPO_ROOT"
    if ! make lint 2>&1; then
      echo "" >&2
      echo "WARNING: compose lint failed after editing $FILE — fix before committing." >&2
      exit 1
    fi
    ;;
esac

exit 0
