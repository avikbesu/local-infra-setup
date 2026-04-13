# CLAUDE.md

Guidance for Claude Code when working in this repository.

For full project documentation see @README.md.
For contribution workflow and change guidelines see @CONTRIBUTING.md.

---

## Quick Commands

| Command | Purpose |
|---------|---------|
| `make ps` | Show all running services and their status |
| `make health` | Check health of all services |
| `make lint` | Validate all compose files parse correctly |
| `make up PROFILES=<p>` | Start services for a given profile |
| `make down` | Stop all services |
| `make logs SERVICE=<s>` | Tail logs for a specific service |
| `make secrets` | Generate secrets from `config/secrets.yaml` |
| `make rotate KEYS=MY_KEY` | Rotate a specific secret |
| `make kube-up` | Bring up all Kubernetes components |
| `make kube-down` | Tear down all Kubernetes components |
| `make kube-deploy-one COMPONENT=<n>` | Deploy a single Helm component |

---

## Repository at a Glance

A modular Docker Compose–based local data engineering platform. Services are grouped by Docker Compose **profiles**; the `makefile` is the sole entry point for all operations — never run `docker compose` directly.

Stack: MinIO · PostgreSQL 16 · Iceberg REST · Trino 435 · Airflow 3 · Fluentd · WireMock 3.10 · Nginx · Kubernetes (kind + Helm).

---

## Key Architecture Constraints

These are non-negotiable design decisions. Violating them breaks the platform.

| Constraint | Why |
|------------|-----|
| All `depends_on` must use `condition: service_healthy` or `condition: service_completed_successfully` | Bare `depends_on` causes race conditions on startup |
| Never pin `latest` image tags | Reproducibility — always use explicit versions |
| Secrets go in `.env.local` only, never in compose files or Helm values | `.env.local` is git-ignored; committed files must be safe to share |
| Use service names as hostnames (`postgres:5432`, not `localhost:5432`) | Services communicate over named Docker networks |
| New compose files in `compose/` are auto-included by the makefile glob | No manual registration needed; adding the file is enough |
| `cluster/helm-components.yaml` is the single registry for Kubernetes components | All K8s deploy/remove/port-forward logic reads from this file |

### Airflow 3 Specifics

- Import namespace: `from airflow.sdk import DAG, dag, task, asset` — never `from airflow import DAG`
- Health check: `GET /api/v2/monitor/health` (not `/health`)
- Secret key env var: `AIRFLOW__API_AUTH__JWT_SECRET` (not `AIRFLOW__API__JWT_SECRET`)
- Scheduler needs `AIRFLOW__CORE__EXECUTION_API_SERVER_URL` set to reach `airflow-api-server`
- The `dags/` directory is a git submodule — never edit files there directly; changes must go through the upstream repo

---

## Best Practices for AI-Assisted Work

### Before Making Changes

1. Run `make lint` to validate all compose files parse correctly before suggesting compose edits
2. Run `make ps` and `make health` to understand current service state before debugging
3. Read the relevant compose file under `compose/` before touching service config
4. Check `config/secrets.yaml` before adding new environment variables — secrets are generated, not hand-written

### When Adding a Service

- Add it to the appropriate `compose/docker-compose.<group>.yaml` (or create a new one — it's auto-included)
- Assign a profile; never add a service to the default (profileless) set
- Add a `healthcheck` block — stateful services require one before downstream `depends_on` will work
- Add `make` targets to the relevant `scripts/make/*.mk` file

### When Adding Kubernetes Components

- Register in `cluster/helm-components.yaml` — don't run `helm install` manually
- Always set resource limits in `helm/<component>/values.yaml`
- Use `condition: service_healthy` in `depends_on` entries within the YAML registry
- Test with `make kube-deploy-one COMPONENT=<name>` before `make kube-up`

### Makefile Rules

- Every new repeatable operation needs a `make` target
- Declare targets in `.PHONY`
- Add a `## Description` comment for `make help` to pick up
- Group targets under the appropriate sub-makefile in `scripts/make/`

### Secrets Rules

- Never hardcode or suggest hardcoding a secret value in any committed file
- New secrets: add the key to `config/secrets.yaml`, then `make secrets` generates the value
- Rotation: `make rotate KEYS=MY_KEY` — never edit `.env.local` directly for rotation

### Code Quality

- Python: PEP 8, type hints, Google-style docstrings, `structlog`, explicit exceptions — see parent `CLAUDE.md` at `infra/.claude/CLAUDE.md`
- Go: wrap errors with `fmt.Errorf("context: %w", err)`, table-driven tests, `slog`/`zap`
- Shell scripts: idempotent where possible; `set -euo pipefail` at the top

### Commits

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
feat:     new service, profile, or capability
fix:      broken healthcheck, config error, dependency ordering
chore:    version bumps, gitignore, tooling
refactor: restructure without behaviour change
docs:     README, FAQ, CONTRIBUTING updates
```

---

## Antipatterns — Never Do These

- Never run raw `docker compose` commands — always go through `make`
- Never use `latest` image tags in compose files or Helm values
- Never put real secrets in any committed file (`.env`, compose YAML, Helm values)
- Never skip health checks on databases or brokers that other services depend on
- Never use bare `depends_on` — always add the `condition:` key
- Never edit files under `dags/` directly — it is a git submodule
- Never bind `cluster-admin` to a workload service account
- Never use `network_mode: host` — use named networks
