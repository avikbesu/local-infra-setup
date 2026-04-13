---
paths:
  - "compose/**"
---

# Docker Compose Rules

## Mandatory Patterns

- All `depends_on` entries MUST use `condition: service_healthy` or `condition: service_completed_successfully` — bare `depends_on` causes race conditions on startup
- Never use `latest` image tags — always pin an explicit version (e.g. `postgres:16-alpine`)
- Every stateful service MUST have a `healthcheck` block before any downstream service can depend on it
- Every service MUST belong to a named Docker network — never use `network_mode: host`
- Every service MUST be assigned a profile — never add a service to the default (profileless) set
- Secrets go in `.env.local` only, never in compose files — reference them via `${VAR_NAME}` only

## After Any Edit

Run `make lint` to validate all compose files parse correctly before considering the change done.

## Adding a New Service

1. Add to the appropriate `compose/docker-compose.<group>.yaml` (or create a new file — it is auto-included by the makefile glob)
2. Assign a profile
3. Add a `healthcheck` block
4. Add corresponding `make` targets in `scripts/make/*.mk`
5. Add a `## Description` comment on each new make target for `make help`

## Hostnames

Services communicate over named Docker networks. Use service names as hostnames:
- `postgres:5432` not `localhost:5432`
- `minio:9000` not `localhost:9000`
