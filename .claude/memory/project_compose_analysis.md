---
name: Docker Compose stack analysis
description: Profiles, service dependencies, resource limits, and known gaps in the compose stack
type: project
---

## Compose files (auto-included by makefile glob `./compose/docker-compose*.yaml`)

| File | Profile | Services |
|------|---------|---------|
| `docker-compose.db.yaml` | `db`, `pipeline`, `query` | postgres, postgres-init (one-shot) |
| `docker-compose.storage.yaml` | `storage` | minio, minio-init (one-shot) |
| `docker-compose.pipeline.yaml` | `pipeline` | airflow-init (one-shot), airflow-api-server, airflow-scheduler, airflow-dag-processor, airflow-triggerer |
| `docker-compose.query.yaml` | `query` | iceberg-rest, trino |
| `docker-compose.logging.yaml` | `logging` | fluentd |
| `docker-compose.mock.yaml` | `mock` | wiremock |
| `docker-compose.proxy.yaml` | `proxy` | nginx |

## Convenience make targets (bypass profile flags)
- `make query` → starts `storage + db + query` profiles
- `make pipeline` → starts `pipeline` profile (postgres via db profile is implicit via depends_on in compose)
- `make up PROFILE=...` → generic profile entry point

## Resource limits state (as of 2026-04-23)

| Service | deploy.resources set? |
|---------|----------------------|
| postgres | ✓ (1 CPU / 1G) |
| minio | ✓ (1 CPU / 1G) |
| airflow-* | ✓ (1 CPU / 1G via anchor) |
| fluentd | ✗ missing |
| wiremock | ✗ missing |
| nginx | ✗ missing |
| iceberg-rest | ✗ missing |
| trino | ✗ missing |

## Image tag state (as of 2026-04-23)

| Service | Tag |
|---------|-----|
| postgres | `${POSTGRES_VERSION:-16-alpine}` ✓ |
| minio | `${MINIO_VERSION:-latest}` ⚠ defaults to latest |
| minio-init (mc) | `minio/mc:latest` ⚠ hardcoded latest |
| airflow-* | `apache/airflow:3.2.0` ✓ |
| iceberg-rest | `iceberg-rest-local:${ICEBERG_REST_VERSION:-0.10.0}` (local build) ✓ |
| trino | `trinodb/trino:${TRINO_VERSION:-435}` ✓ |
| fluentd | `fluentd-local:latest` (local build — always overwritten) ⚠ |
| wiremock | `wiremock/wiremock:${WIREMOCK_VERSION:-3.10.0-1}` ✓ |
| nginx | `nginx:${NGINX_IMAGE_TAG:-1.27-alpine}` ✓ |

## Key dependency chains

```
postgres (healthy) → postgres-init (success) → iceberg-rest
minio (healthy) → minio-init (success) → iceberg-rest
iceberg-rest (healthy) → trino

postgres (healthy) → airflow-init (success) → airflow-api-server + airflow-scheduler + airflow-dag-processor + airflow-triggerer
airflow-api-server (healthy) → airflow-scheduler (additional dep)

minio (healthy) → fluentd
```

## Known gaps / TODOs
- `config/postgres/setup.sh` missing `set -euo pipefail`; uses `$(ls ...)` anti-pattern (GAP-S1 / issue #20)
- `minio/minio:latest` and `minio/mc:latest` unpinned (issue #30)
- Fluentd, WireMock, Nginx, Iceberg REST, Trino have no deploy.resources (issue #33/#23/#6)
- Nginx compose has no `depends_on` — may cause 502s on fresh stack startup (GAP-C7)
- `postgres-init` excluded from `pipeline` profile intentionally (iceberg DB not needed for airflow-only) — should be documented (GAP-C2)
- Fluentd logging for Airflow is commented out in compose (driver config present but disabled)

**Why:** Reference this to understand which profiles to start together and what gaps remain before touching service config.
**How to apply:** When adding a new compose service, follow the resource limits and healthcheck patterns from postgres/airflow. When debugging startup ordering, trace the depends_on chain above.
