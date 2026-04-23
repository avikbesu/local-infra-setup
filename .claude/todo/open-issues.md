# Open GitHub Issues — Priority Tracker

Last reviewed: 2026-04-23. Issues synced from GitHub. Closed items removed; newly resolved items noted.

---

## CRITICAL

| # | Title | Notes |
|---|-------|-------|
| [#20](../../..) | Fix shell script error handling with `set -euo pipefail` | All `scripts/*.sh` already fixed; **remaining gap**: `config/postgres/setup.sh` still missing `set -euo pipefail` and uses `$(ls ...)` anti-pattern in for loop |
| [#18](../../..) | Remove hardcoded default passwords from Docker Compose | `${POSTGRES_PASSWORD:-airflow}` fallback in pipeline compose is the main risk. Also minio uses `${MINIO_ROOT_PASSWORD:?...}` (fails hard — OK). Postgres compose uses `:?` (OK). Airflow compose has `:-airflow` fallback — bad. |
| [#17](../../..) | Pin all Docker image tags to specific versions with digest verification | `minio/minio:latest` and `minio/mc:latest` in `compose/docker-compose.storage.yaml`. `fluentd-local:latest` is a locally built image (lower risk but still unpinned). |
| [#4](../../..)  | Add securityContext to all containers to limit privileges | No securityContext on any Compose service. No runAsNonRoot/readOnlyRootFilesystem. |
| [#3](../../..)  | Remove hardcoded secrets from Kubernetes Helm values | `helm/minio/values.yaml` has `rootPassword: "minio123"` hardcoded. Postgres and Airflow are already fixed. |

---

## HIGH

| # | Title | Notes |
|---|-------|-------|
| [#24](../../..) / [#31](../../..) | Fix Iceberg REST entrypoint log filtering and signal handling | `JAVA_TOOL_OPTIONS` / logback.xml approach is commented out in compose. Entrypoint `entrypoint.sh` may still use grep-based credential suppression. |
| [#23](../../..) / [#33](../../..) | Add resource limits to WireMock and Fluentd (Compose) | Compose `docker-compose.mock.yaml` has no `deploy.resources`. `docker-compose.logging.yaml` (fluentd) has no `deploy.resources`. Nginx compose also lacks limits. |
| [#22](../../..) / [#5](../../..)  | Implement network segmentation (Docker networks + K8s NetworkPolicies) | All compose services share one implicit network. No NetworkPolicy resources in any Helm chart. |
| [#21](../../..) | Add security contexts to Kubernetes Airflow pods | `helm/airflow/values.yaml` has no `securityContext` or `podSecurityContext` override. |
| [#8](../../..)  | Implement authentication/authorization for all service endpoints | Trino has no auth. Iceberg REST has no auth. MinIO uses root credentials everywhere. |
| [#7](../../..)  | Enable HTTPS/TLS for all inter-service communication | Everything runs plain HTTP internally. |
| [#6](../../..)  | Add resource limits to all services (CPU, memory) | Partially done: postgres/airflow/minio have limits in compose. Missing: wiremock, fluentd, nginx in compose. |

---

## MEDIUM

| # | Title | Notes |
|---|-------|-------|
| [#38](../../..) | Expand CONTRIBUTING.md with Kubernetes troubleshooting and deployment guidance | Pure docs — no code change required. |
| [#36](../../..) | Document why postgres and minio are disabled in helm-components.yaml | `postgres` is in helm-components but `enabled: false`; likely because it's managed separately. Needs inline comment in `cluster/helm-components.yaml`. |
| [#35](../../..) | README has outdated healthcheck note and port inconsistency for Airflow | Airflow health endpoint changed from `/health` to `GET /api/v2/monitor/health` in Airflow 3. |
| [#34](../../..) | Incomplete .PHONY declarations | Missing: `dagcheck`, `build-query`, `query`, `pipeline`, `sync`, `secrets`, `rotate`. Present in first block but kube-* targets each have their own .PHONY line (OK). |
| [#26](../../..) | Implement Kubernetes resource quotas and namespace limits | No ResourceQuota in `db`, `af`, or `misc` namespaces. |
| [#25](../../..) | Add security headers to Nginx proxy | `helm/nginx/values.yaml` serverBlock missing `X-Frame-Options`, `X-Content-Type-Options`, `Content-Security-Policy`, etc. Same for compose nginx. |
| [#15](../../..) | Add Pod Disruption Budgets for high availability | No PDB resources in any Helm chart or `extraObjects`. |
| [#14](../../..) | Document and enforce secret rotation policy | `make rotate KEYS=...` exists; no runbook or cron for mandatory rotation. |
| [#13](../../..) | Add API rate limiting and DDoS protection | Nginx has no `limit_req` zones. |
| [#12](../../..) | Implement data backup and disaster recovery strategy | No backup job for postgres PV or minio data. |
| [#11](../../..) | Add RBAC restrictions for Kubernetes service accounts | Airflow SA has a batch Role scoped to `af` namespace — OK. Other SAs use default cluster RBAC. |
| [#10](../../..) | Implement container image vulnerability scanning | No Trivy/Grype step in CI or pre-commit. |
| [#9](../../..)  | Enable comprehensive audit logging across all services | Fluentd only covers compose stack; no K8s audit log forwarding. |

---

## LOW

| # | Title | Notes |
|---|-------|-------|
| [#39](../../..) | Add pre-commit hook to block secrets and validate compose files | Hooks exist in `.claude/hooks/` (Claude-specific) but no git pre-commit hook (`.pre-commit-config.yaml` at root). |
| [#16](../../..) | Add comprehensive security documentation | Purely additive docs work. |

---

## META / TRACKING

| # | Title |
|---|-------|
| [#28](../../..) | [META] Security & Best Practices Audit - Priority Tracking |

---

## Recently Closed (for reference)

| # | Title | Closed | Notes |
|---|-------|--------|-------|
| #40 | makefile: remove or implement unused ENV variable | 2026-04-15 | ENV removed; help text still mentions it — minor cleanup pending |
| #37 | config: expand .gitignore | 2026-04-15 | Done |
| #27 | Improve Python code quality | 2026-04-15 | Done |
| #29 | Rotate all secrets | 2026-04-23 | Done |
| #32 | Hardcoded placeholder secret in helm/airflow/values.yaml | **Closed 2026-04-23** | Fixed: `webserverSecretKeySecretName` now used |
| #19 | Replace hardcoded Airflow webserver secret with K8s Secret | **Closed 2026-04-23** | Fixed: `fernetKeySecretName` + `webserverSecretKeySecretName` in values.yaml |

## New Issues Created from Gap Analysis (2026-04-23)

| # | Gap | Priority |
|---|-----|---------|
| [#45](../../..) | docker: airflow-init silently swallows user-creation errors | HIGH |
| [#46](../../..) | docker: nginx compose missing depends_on — intermittent 502 on startup | MEDIUM |
| [#47](../../..) | docker: nginx compose missing resource limits | MEDIUM |
| [#48](../../..) | docker: minio-init bucket loop fragile | LOW |
| [#49](../../..) | docs: postgres-init pipeline profile exclusion undocumented | LOW |
| [#50](../../..) | kubernetes: nginx Helm /minio/ routes always 502 (MinIO disabled) | MEDIUM |
| [#51](../../..) | kubernetes: enabling MinIO requires manual steps not in kube-secrets.sh | MEDIUM |
| [#52](../../..) | kubernetes: Airflow task logs not persisted — lost on pod restart | MEDIUM |
| [#53](../../..) | makefile: help text still advertises removed ENV variable | LOW |
| [#54](../../..) | kubernetes: Airflow probe tuning inconsistent across components | MEDIUM |
| [#55](../../..) | scripts: cluster/install.sh missing shebang and error handling | LOW |
