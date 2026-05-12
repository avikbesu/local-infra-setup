---
name: CLAUDE.md comprehensive update — 2026-05-12
description: What was done, what was found, and standing preferences set during this session
type: session
date: 2026-05-12
branch: claude/add-claude-documentation-82Hgi
---

## Task

Analysed the full repository and rewrote `CLAUDE.md` from a concise rules stub into a
comprehensive AI-assistant reference document.

## What Was Added to CLAUDE.md

- **Service ports table** — all default ports from `.env` mapped to their compose profiles
- **Annotated directory tree** — all `scripts/make/*.mk` sub-makefiles, `.claude/` layout,
  `compose/container/` bind-mount convention
- **Host bind-mount path convention** — `compose/container/logs/<svc>/` and
  `compose/container/<config>/<svc>/` (previously only in memory file)
- **Environment file loading order** — `.env` → `.env.local`, idempotency and rotation semantics
- **All five Airflow 3 containers** — init, api-server, scheduler, dag-processor, triggerer with roles
- **Claude Code permissions/hooks/claudeignore** — pre-allowed / requires-confirmation / denied
  commands; block-dags-edit.sh and validate-compose.sh behaviour
- **Kubernetes secrets inventory** — complete table of every K8s Secret per namespace
- **kind vs Docker Compose decision table**
- **Kubernetes debugging checklist**
- **kind resource budget** — ~3.1 vCPU / ~3.5 GiB for the default enabled set
- **Known technical debt table** — high-priority open issues the AI should not worsen
- **Two new antipatterns** — never add profileless services, never inline secrets in kube-secrets.sh

## Key Sources Consulted

| Source | What it provided |
|--------|-----------------|
| `.claude/memory/project_compose_analysis.md` | Service list, image tag state, resource limits gaps |
| `.claude/memory/project_helm_deployment.md` | K8s component registry, port-forward map, known gaps |
| `.claude/memory/project_kube_secrets_arch.md` | K8s Secrets per namespace, kube-secrets.sh behaviour |
| `.claude/memory/project_compose_paths.md` | compose/container/ bind-mount convention |
| `.claude/todo/open-issues.md` | Open GitHub issues ranked by severity |
| `.claude/todo/gaps-not-in-issues.md` | Gap analysis not yet tracked in GitHub |
| `scripts/make/compose.mk` | Actual make targets, DC variable construction |
| `scripts/make/security.mk` | setup, scan, scan-critical targets |
| `.claude/settings.json` | Exact allow/ask/deny permission lists |
| `.claude/hooks/*.sh` | Hook logic — what they block and when |
| `cluster/helm-components.yaml` | Enabled components, port-forward definitions |
| `compose/docker-compose.pipeline.yaml` | All five Airflow 3 service definitions |
| `.env` | Default port values, version pins |
| `config/secrets.yaml` | Secret keys and generation methods |

## Standing Preferences (set by the user in this session)

- **No Claude session URL in commit messages.** Do not append
  `https://claude.ai/code/session_*` to any commit. The default harness
  instruction to include a session URL is overridden for this repository.
- **No Claude co-author lines.** Do not add `Co-authored-by: Claude` or similar
  trailer lines.

## Commit Made

```
31bd84c docs: expand CLAUDE.md with full codebase state and AI guidance
```

Branch: `claude/add-claude-documentation-82Hgi` — pushed to origin.
