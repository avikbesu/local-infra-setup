Commit all staged and unstaged changes, then push to the remote. Optionally switch to a new or existing branch first.

Uses the **GitHub MCP server** (`mcp__github__*`) for all GitHub API operations — branch sync checks, PR lookup, and PR creation. Local git operations (staging, committing, pushing) still go through git.

## Arguments

`$ARGUMENTS` may be:
- Empty — commit and push on the current branch
- A branch name — switch to that branch (create it if it doesn't exist), then commit and push

---

## Steps

### 0. Resolve repository identity

Run `git remote get-url origin` to get the remote URL. Parse `owner` and `repo` from it — handles both SSH (`git@github.com:owner/repo.git`) and HTTPS (`https://github.com/owner/repo.git`) formats. You will need these for every `mcp__github__*` call.

### 1. Validate branch sync with remote

Run `git branch --show-current` to get the current branch name.

Call `mcp__github__get_branch` with `{ owner, repo, branch }` to get the remote branch state.

- If the call returns a `404` / branch not found — the branch is new and has no remote counterpart yet. Skip the sync check and continue.
- If the remote branch exists, compare its SHA against local HEAD (`git rev-parse HEAD`):
  - **SHAs match** — branch is in sync, continue.
  - **SHAs differ** — the remote has commits the local branch does not. Tell the user, then run:
    ```bash
    git pull --rebase origin <branch>
    ```
    If the rebase fails (conflicts), stop immediately and tell the user to resolve conflicts before re-running. Do NOT continue with an unresolved rebase.

### 2. Show current state

Run these in parallel:
- `git status` — see what's changed
- `git log --oneline -5` — check recent commits and message style

### 3. Handle branch switching (only if a branch name was given)

If `$ARGUMENTS` is non-empty:
- Check if the branch already exists: `git branch --list "$ARGUMENTS"`
- If it exists: `git checkout "$ARGUMENTS"`
- If it doesn't exist: `git checkout -b "$ARGUMENTS"`
- After switching, confirm with `git branch --show-current`
- Re-run Step 1 sync check for the new branch before continuing.

### 4. Stage all changes

```bash
git add -A
```

Before staging, scan the list of files to be committed. If any look like they could contain secrets (`.env`, `.env.*`, `*.pem`, `*.key`, `*.p12`, `*-secret.yaml`, `kubeconfig`), warn the user and **do NOT stage them**. Ask for explicit confirmation before proceeding.

### 5. Draft a commit message

- Read `git diff --cached` to understand what changed
- Follow Conventional Commits: `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`
- One-line subject (imperative mood, ≤72 chars); add a body only if the change warrants explanation

### 6. Commit

```bash
git commit -m "$(cat <<'EOF'
<subject line>

<optional body>
EOF
)"
```

If the pre-commit hook fails: fix the issue, re-stage, and create a **new** commit — never amend.

### 7. Push

```bash
git push -u origin $(git branch --show-current)
```

If the push is rejected because the remote diverged since Step 1 (race condition), tell the user — do NOT force-push. Suggest they re-run `/push-changes` which will pick up the sync check again.

### 8. Report via GitHub MCP

After a successful push, use `mcp__github__list_pull_requests` with `{ owner, repo, state: "open", head: "<owner>:<branch>" }` to check whether a PR already exists for this branch.

**PR exists**: Report the PR number, title, and URL.

**No PR exists**: Create one with `mcp__github__create_pull_request`:
- `title`: the commit subject line
- `body`: a two-section markdown body —
  ```
  ## Summary
  <1–3 bullet points describing what changed and why>

  ## Test plan
  - [ ] <key thing to verify>
  - [ ] Check for regressions in related areas

  🤖 Generated with [Claude Code](https://claude.com/claude-code)
  ```
- `base`: the repo default branch (usually `main`)
- `head`: the current branch

Print a final summary:
- Branch pushed to
- Commit hash and subject line
- PR URL (existing or newly created)
