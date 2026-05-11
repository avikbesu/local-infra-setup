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
| `make up PROFILE=<p>` | Start services for a given profile |
| `make down` | Stop all services |
| `make logs SERVICE=<s>` | Tail logs for a specific service |
| `make shell SERVICE=<s>` | Open a shell in a running container |
| `make secrets` | Generate secrets from `config/secrets.yaml` |
| `make rotate KEYS=MY_KEY` | Rotate a specific secret |
| `make setup` | Activate git pre-commit hooks (run once per clone) |
| `make scan` | Scan pinned images for HIGH/CRITICAL CVEs (requires `trivy`) |
| `make scan-critical` | CVE scan with non-zero exit on CRITICAL (CI gate) |
| `make query` | Start query stack (Trino + Iceberg REST + Postgres + MinIO) |
| `make pipeline` | Start pipeline stack (Airflow + Postgres) |
| `make dagcheck` | Validate all Airflow DAGs for import errors |
| `make kube-up` | Bring up all Kubernetes components |
| `make kube-down` | Tear down all Kubernetes components |
| `make kube-deploy-one COMPONENT=<n>` | Deploy a single Helm component |
| `make kube-validate-render` | Validate registry + helm template dry-run (no cluster) |
| `make kube-status` | Show cluster, releases, pods, and port-forward status |
| `make kube-port-forward` | Start background port-forwards for all components |
| `make obs-up` | Start observability stack (Prometheus + Grafana + cAdvisor) |
| `make proxy-up` | Start full stack + nginx reverse proxy |

---

## Repository at a Glance

A modular Docker Compose–based local data engineering platform. Services are grouped by Docker Compose **profiles**; the `makefile` is the sole entry point for all operations — never run `docker compose` directly.

Stack: MinIO · PostgreSQL 16 · Iceberg REST · Trino 435 · Airflow 3 · Fluentd · WireMock 3.10 · Nginx · Prometheus · Grafana · Kubernetes (kind + Helm).

### Service Ports (defaults from `.env`)

| Service | Port(s) | Profile |
|---------|---------|---------|
| MinIO API | 9000 | `storage`, `pipeline` |
| MinIO Console | 9001 | `storage`, `pipeline` |
| PostgreSQL | 5432 | `db`, `pipeline`, `query` |
| Iceberg REST | 8181 | `query` |
| Trino | 8080 | `query` |
| Airflow API Server (UI + REST) | 8081 | `pipeline` |
| Fluentd | 24224 | `logging`, `pipeline` |
| WireMock | 8090 | `mock` |
| Nginx | 80 | `proxy` |
| Prometheus | 9090 | `observability` |
| Grafana | 3000 | `observability` |

---

## Directory Structure

```
compose/                    # One yaml per service group (auto-included by makefile glob)
  docker-compose.db.yaml       # postgres, postgres-init          [profiles: db, pipeline, query]
  docker-compose.storage.yaml  # minio, minio-init                [profiles: storage, pipeline]
  docker-compose.logging.yaml  # fluentd                          [profiles: logging, pipeline]
  docker-compose.query.yaml    # iceberg-rest, trino              [profile: query]
  docker-compose.pipeline.yaml # airflow-* (5 services)           [profile: pipeline]
  docker-compose.mock.yaml     # wiremock                         [profile: mock]
  docker-compose.proxy.yaml    # nginx                            [profile: proxy]
  docker-compose.observability.yaml # prometheus, grafana, cadvisor [profile: observability]
  fluentd/                  # Fluentd Dockerfile + fluent.conf
  iceberg-rest/             # Custom Iceberg REST Dockerfile + entrypoint.sh
  trino/                    # Trino catalog/node config
  nginx/                    # Nginx vhost config
  prometheus/               # Prometheus scrape config
  grafana/                  # Grafana datasource + dashboard provisioning
  wiremock/                 # WireMock stub mappings
  container/                # Host bind-mounts (logs, plugins, data) — git-ignored
scripts/
  make/                     # Sub-makefiles included by root makefile
    compose.mk              # Core Docker Compose lifecycle targets
    query.mk                # Trino SQL + Iceberg REST API targets
    mock.mk                 # WireMock targets
    ollama.mk               # Ollama LLM targets
    proxy.mk                # Nginx reverse proxy targets
    security.mk             # Image scanning + hook setup targets
    observability.mk        # Prometheus/Grafana/cAdvisor targets
  *.sh                      # Shell scripts for cluster ops, secret gen, health checks
cluster/
  helm-components.yaml      # Single registry for all K8s/Helm components
  kind-config.yaml          # kind cluster config
helm/
  <component>/values.yaml   # Helm values per component
config/
  secrets.yaml              # Declarative secret definitions (generates .env.local)
  postgres/setup.sh         # One-shot DB provisioning script
dags/                       # Git submodule (airflow3-by-example) — NEVER edit directly
.claude/
  settings.json             # Claude Code permissions + hooks
  hooks/                    # block-dags-edit.sh, validate-compose.sh
  rules/                    # Domain-specific rule files (airflow.md, compose.md, k8s.md)
  memory/                   # Persistent project memory files
```

### Host Bind-Mount Path Convention

All Docker Compose volume mounts follow this layout under `compose/container/`:

- **Logs:** `compose/container/logs/<service_name>/`
- **Other configs (plugins, data, config files):** `compose/container/<config_name>/<service_name>/`

Always use these paths when adding volume mounts for new services.

---

## Key Architecture Constraints

These are non-negotiable design decisions. Violating them breaks the platform.

| Constraint | Why |
|------------|-----|
| All `depends_on` must use `condition: service_healthy` or `condition: service_completed_successfully` | Bare `depends_on` causes race conditions on startup |
| Never pin `latest` image tags | Reproducibility — always use explicit versions |
| Secrets go in `.env.local` only, never in compose files or Helm values | `.env.local` is git-ignored; committed files must be safe to share |
| Use service names as hostnames (`postgres:5432`, not `localhost:5432`) | Services communicate over named Docker networks |
| Every service must belong to a named profile — never add profileless services | Profileless services start on every `make up` regardless of intent |
| Every service must use a named Docker network — never `network_mode: host` | Isolates traffic and enables service-name resolution |
| New compose files in `compose/` are auto-included by the makefile glob | No manual registration needed; adding the file is enough |
| `cluster/helm-components.yaml` is the single registry for Kubernetes components | All K8s deploy/remove/port-forward logic reads from this file |

### Airflow 3 Specifics

Airflow 3 replaced `webserver` with `api-server`. The pipeline stack runs five containers:

| Container | Role |
|-----------|------|
| `airflow-init` | One-shot: DB migrate + admin user creation |
| `airflow-api-server` | UI (React) + REST API + Task Execution Interface |
| `airflow-scheduler` | Triggers DAG runs; needs `AIRFLOW__CORE__EXECUTION_API_SERVER_URL` |
| `airflow-dag-processor` | Parses DAG files (separated from scheduler in Airflow 3) |
| `airflow-triggerer` | Handles deferrable operators |

Critical env vars and endpoints:

| Item | Correct value | Wrong value |
|------|---------------|-------------|
| Import namespace | `from airflow.sdk import DAG, dag, task, asset` | `from airflow import DAG` |
| Health check | `GET /api/v2/monitor/health` | `GET /health` (Airflow 2 path) |
| JWT secret env var | `AIRFLOW__API_AUTH__JWT_SECRET` | `AIRFLOW__API__JWT_SECRET` |
| Execution API env var | `AIRFLOW__CORE__EXECUTION_API_SERVER_URL` | — |

The `dags/` directory is a **git submodule** — never edit files there directly. Changes must go through the upstream `airflow3-by-example` repo.

---

## Environment Variables & Secrets

Environment files load in order; later values win:

1. `.env` — non-secret defaults, committed to git
2. `.env.local` — secrets and local overrides, **git-ignored**, auto-generated by `make secrets` / `make up`

Secret definitions live in `config/secrets.yaml`. Supported methods: `static`, `random_base64`, `random_hex`, `fernet`. The generator is idempotent — existing keys in `.env.local` are never overwritten.

```bash
# Add a key to config/secrets.yaml, then:
make secrets          # appends new keys; existing keys untouched

make rotate KEYS=MINIO_ROOT_PASSWORD,AIRFLOW_SECRET_KEY   # force-regenerates named keys only
```

Never hardcode secret values in any committed file. Never suggest editing `.env.local` directly.

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
- Add `deploy.resources` limits (CPU + memory) — model after the postgres/airflow anchors
- Add `make` targets to the relevant `scripts/make/*.mk` file
- Place host bind-mount paths under `compose/container/` following the established convention

### When Adding Kubernetes Components

- Register in `cluster/helm-components.yaml` — don't run `helm install` manually
- Always set resource limits in `helm/<component>/values.yaml`
- Add required secrets to `scripts/kube-secrets.sh` (not to values files)
- Use `condition: service_healthy` in `depends_on` entries within the YAML registry
- Test with `make kube-deploy-one COMPONENT=<name>` before `make kube-up`

### When Adding Kubernetes Secrets

K8s Secrets are created by `make kube-secrets` (runs `scripts/kube-secrets.sh`) before any Helm deploy. The script is idempotent (`--dry-run=client | kubectl apply`). Existing secrets per namespace:

| Secret | Namespace | Keys | Used by |
|--------|-----------|------|---------|
| `postgres-credentials` | `db` | `password`, `postgres-password` | bitnami/postgresql `auth.existingSecret` |
| `airflow-metadata` | `af` | `connection` (SQLAlchemy URI) | airflow chart `data.metadataSecretName` |
| `airflow-webserver` | `af` | `webserver-secret-key` | airflow chart `webserverSecretKeySecretName` |
| `airflow-fernet` | `af` | `fernet-key` | airflow chart `fernetKeySecretName` |
| `minio-credentials` | `s3` | `rootUser`, `rootPassword` | minio chart `existingSecret` |
| `wiremock-stubs` (ConfigMap) | `misc` | stub files | WireMock deployment |

Kubernetes namespaces: `db` (postgres) · `af` (airflow) · `s3` (minio) · `misc` (nginx + wiremock)

### Makefile Rules

- Every new repeatable operation needs a `make` target
- Declare targets in `.PHONY`
- Add a `## Description` comment for `make help` to pick up
- Group targets under the appropriate sub-makefile in `scripts/make/`
- Never expose `docker compose` directly — all operations go through `make`

### Secrets Rules

- Never hardcode or suggest hardcoding a secret value in any committed file
- New secrets: add the key to `config/secrets.yaml`, then `make secrets` generates the value
- Rotation: `make rotate KEYS=MY_KEY` — never edit `.env.local` directly for rotation

### Code Quality

- Python: PEP 8, type hints, Google-style docstrings, `structlog`, explicit exceptions
- Go: wrap errors with `fmt.Errorf("context: %w", err)`, table-driven tests, `slog`/`zap`
- Shell scripts: idempotent where possible; `set -euo pipefail` at the top; use glob patterns not `$(ls ...)`

### Commits

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
feat:     new service, profile, or capability
fix:      broken healthcheck, config error, dependency ordering
chore:    version bumps, gitignore, tooling
refactor: restructure without behaviour change
docs:     README, FAQ, CONTRIBUTING updates
```

Branch naming: `feat/<short-description>`, `fix/<issue-description>`, `chore/<task>`.

---

## Claude Code Configuration

### Permissions (`.claude/settings.json`)

Pre-allowed (no prompt): `Read`, `Edit`, `Glob`, `Grep`, all `make *` commands, `git` read/write commands.

Requires confirmation: `docker *`, `kubectl *`, `helm *`, `kind *`, `WebFetch`.

Denied: `docker compose *` (must go through `make`), `docker-compose *`, `rm -rf *`.

### Hooks

- **PreToolUse (Edit/Write):** `block-dags-edit.sh` — blocks any edit targeting `dags/` (git submodule; changes must go upstream)
- **PostToolUse (Edit/Write):** `validate-compose.sh` — runs `make lint` asynchronously after any edit to a `compose/*.yaml` file; prints a warning if lint fails

### `.claudeignore`

Excluded from Claude's view: `dags/`, `compose/container/`, `**/logs/**`, `.env.local`, `**/*.pem`, `**/*.key`, `helm/**/Chart.lock`, OS/editor noise.

---

## Kubernetes Quick Reference

### When to Use kind vs Docker Compose

| Scenario | Use |
|----------|-----|
| Day-to-day data engineering / DAG development | Docker Compose (`make up`) |
| Testing a new Helm chart or K8s manifest | kind (`make kube-deploy-one`) |
| Validating K8s RBAC, secrets, or probe behaviour | kind |
| Running the full query stack (Trino + Iceberg + MinIO) | Docker Compose (`make query`) |
| Reproducing a production-like K8s environment | kind |

### Enabled Components (kind cluster)

Default enabled set: postgres · airflow · wiremock · nginx. MinIO is registered but `enabled: false` — it requires extra setup (create `s3` namespace, run `make kube-secrets`).

**Resource budget (single-node kind):** ~3.1 vCPU / ~3.5 GiB. Recommended host: 4 vCPU / 6 GiB free.

### Kubernetes Debugging Checklist

| Symptom | First command |
|---------|---------------|
| Pod stuck in `Pending` | `kubectl describe pod <pod> -n <ns>` → check Events |
| `CrashLoopBackOff` | `kubectl logs <pod> -n <ns> --previous` |
| `OOMKilled` | Increase `resources.limits.memory` in `helm/<component>/values.yaml` |
| `ImagePullBackOff` | Verify image tag is pinned and registry is reachable |
| Helm install times out | Check `depends_on` components are healthy first; increase `wait_timeout` |
| RBAC errors | `kubectl auth can-i <verb> <resource> --as=system:serviceaccount:<ns>:<sa>` |
| Secret missing | Confirm `make kube-secrets` ran; check with `kubectl get secret -n <ns>` |
| Port-forward not working | `make kube-port-forward-stop && make kube-port-forward` |

---

## Known Technical Debt

These are open issues — avoid patterns that worsen them, and fix them when touching the relevant file.

| Issue | Location | Severity |
|-------|----------|---------|
| `minio/minio:latest` and `minio/mc:latest` unpinned | `compose/docker-compose.storage.yaml` | HIGH |
| `helm/minio/values.yaml` has `rootPassword: "minio123"` hardcoded | `helm/minio/values.yaml` | HIGH |
| No securityContext on any compose service | All compose files | HIGH |
| Hardcoded `${POSTGRES_PASSWORD:-airflow}` fallback in pipeline compose | `docker-compose.pipeline.yaml` | HIGH |
| `config/postgres/setup.sh` missing `set -euo pipefail` and uses `$(ls ...)` | `config/postgres/setup.sh` | MEDIUM |
| Fluentd, WireMock, Nginx, Iceberg REST, Trino have no `deploy.resources` in compose | `docker-compose.logging/mock/proxy/query.yaml` | MEDIUM |
| Nginx compose has no `depends_on` — may 502 on fresh stack startup | `docker-compose.proxy.yaml` | MEDIUM |
| Nginx K8s routes `/minio/` and `/minio-api/` point to disabled MinIO (502) | `helm/nginx/values.yaml` | MEDIUM |
| No NetworkPolicy resources in any Helm chart | `helm/*/` | MEDIUM |
| K8s Airflow task logs not persisted (`logs.persistence.enabled: false`) | `helm/airflow/values.yaml` | MEDIUM |
| No securityContext on K8s Airflow pods | `helm/airflow/values.yaml` | MEDIUM |

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
- Never add a service to the profileless (default) set — always assign a profile
- Never add secrets to `scripts/kube-secrets.sh` values inline — source them from `.env.local`
