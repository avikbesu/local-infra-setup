Commit all staged and unstaged changes, then push to the remote. Optionally switch to a new or existing branch first.

## Arguments

`$ARGUMENTS` may be:
- Empty — commit and push on the current branch
- A branch name — switch to that branch (create it if it doesn't exist), then commit and push

## Steps

### 1. Show current state

Run these in parallel:
- `git status` — see what's changed
- `git log --oneline -5` — check recent commits and message style
- `git branch --show-current` — confirm the active branch

### 2. Handle branch switching (only if a branch name was given)

If `$ARGUMENTS` is non-empty:
- Check if the branch already exists: `git branch --list "$ARGUMENTS"`
- If it exists: `git checkout "$ARGUMENTS"`
- If it doesn't exist: `git checkout -b "$ARGUMENTS"`
- After switching, confirm with `git branch --show-current`

### 3. Stage all changes

```bash
git add -A
```

If any file looks like it might contain secrets (`.env`, `*.pem`, `*.key`, `*-secret.yaml`), warn the user and do NOT stage it. Ask for confirmation before proceeding.

### 4. Draft a commit message

- Read `git diff --cached` to understand what changed
- Follow Conventional Commits: `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`
- One-line subject (imperative mood, ≤72 chars); add a body only if the change needs explanation
- Append the co-author trailer

### 5. Commit

```bash
git commit -m "$(cat <<'EOF'
<subject line>

<optional body>

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

If the pre-commit hook fails: fix the issue, re-stage, and create a **new** commit — never amend.

### 6. Push

Push to the remote tracking branch:

```bash
git push -u origin $(git branch --show-current)
```

If the push is rejected because the remote has commits the local branch doesn't have, tell the user — do NOT force-push. Suggest `git pull --rebase` and let them decide.

### 7. Report

Print a short summary:
- Branch pushed to
- Commit hash and subject line
- Remote URL / PR link if `gh` CLI is available (`gh pr view --web` or suggest `gh pr create`)
