#!/usr/bin/env bash
# PreToolUse hook — blocks any Edit or Write targeting the dags/ submodule.
# dags/ is a git submodule; changes must go through the upstream repository.
set -euo pipefail

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [[ -z "$FILE" ]]; then
  exit 0
fi

# Resolve to an absolute path for reliable prefix matching
REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null || echo "")"
if [[ -n "$REPO_ROOT" ]]; then
  DAGS_PATH="$REPO_ROOT/dags"
  case "$FILE" in
    "$DAGS_PATH"*|"dags/"*|"./dags/"*)
      echo "Blocked: dags/ is a git submodule — changes must go through the upstream DAGs repository." >&2
      exit 2
      ;;
  esac
fi

exit 0
