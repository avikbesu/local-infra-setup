# Local Infrastructure Setup

A modular Docker Compose–based local data engineering platform covering object storage, distributed SQL, workflow orchestration, and centralised log shipping.

---

## Table of Contents

- [Overview](#overview)
- [Docker Compose](#docker-compose)
  - [Container Dependency Diagram](#container-dependency-diagram)
  - [Compose Files](#compose-files)
  - [Quick Start](#quick-start)

---

## Overview

| Component | Technology | Purpose |
|-----------|-----------|---------|
| Object Storage | MinIO | S3-compatible local data lake storage |
| Catalog | Iceberg REST + PostgreSQL | Apache Iceberg table catalog (JDBC-backed) |
| Query Engine | Trino | Distributed SQL over Iceberg tables |
| Orchestration | Apache Airflow 3 | DAG-based workflow scheduling |
| Log Shipping | Fluentd | Centralised log aggregation → MinIO |

---

## Docker Compose

The infrastructure is split across multiple Compose files inside the `compose/` directory, grouped by concern. Docker Compose **profiles** control which services start together.

### Container Dependency Diagram

```mermaid
flowchart TD
    subgraph STORAGE["🗄️ Storage Stack"]
        minio["MinIO\nObject Storage\n:9000 / :9001"]
        minio_init["minio-init\none-shot bucket setup"]
    end

    subgraph DB["🐘 Database Stack"]
        postgres["PostgreSQL\n:5432"]
    end

    subgraph CATALOG["🧊 Catalog & Query Stack"]
        iceberg_rest["Iceberg REST Catalog\n:8181"]
        trino["Trino\n:8080"]
    end

    subgraph LOGGING["📋 Logging Stack"]
        fluentd["Fluentd\n:24224"]
    end

    subgraph PIPELINE["⚡ Pipeline Stack — Airflow 3"]
        airflow_init["airflow-init\none-shot DB migrate"]
        airflow_scheduler["airflow-scheduler"]
        airflow_api["airflow-api-server\nUI + REST API\n:8080"]
    end

    minio          -- "healthy"    --> minio_init
    minio          -- "healthy"    --> fluentd

    postgres       -- "healthy"    --> iceberg_rest
    minio_init     -- "completed"  --> iceberg_rest
    iceberg_rest   -- "healthy"    --> trino

    postgres       -- "healthy"    --> airflow_init
    postgres       -- "healthy"    --> airflow_scheduler
    airflow_init   -- "completed"  --> airflow_scheduler
    postgres       -- "healthy"    --> airflow_api
    airflow_scheduler -- "healthy" --> airflow_api

    airflow_scheduler -. "log driver" .-> fluentd
    airflow_api       -. "log driver" .-> fluentd
```

> **Legend**
> - Solid arrows (`-->`) = `depends_on` startup condition
> - Dashed arrows (`-.->`) = Fluentd logging driver (async, not a hard startup dependency)

### Compose Files

| File | Profile(s) | Services |
|------|-----------|---------|
| `docker-compose.yml` | _(default / core iceberg stack)_ | `minio`, `minio-init`, `postgres`, `iceberg-rest`, `trino` |
| `docker-compose.storage.yaml` | `storage`, `pipeline` | `minio`, `minio-init` |
| `docker-compose.db.yaml` | `db`, `pipeline`, `query` | `postgres` |
| `docker-compose.logging.yaml` | `logging`, `pipeline` | `fluentd` |
| `docker-compose.pipeline.yaml` | `pipeline` | `airflow-init`, `airflow-scheduler`, `airflow-api-server` |

### Quick Start

```bash
# Full pipeline stack (storage + db + logging + airflow)
docker compose \
  -f compose/docker-compose.storage.yaml \
  -f compose/docker-compose.db.yaml \
  -f compose/docker-compose.logging.yaml \
  -f compose/docker-compose.pipeline.yaml \
  --profile pipeline up -d

# Core iceberg/trino stack only (docker-compose.yml)
docker compose -f compose/docker-compose.yml up -d

# Storage + logging only
docker compose \
  -f compose/docker-compose.storage.yaml \
  -f compose/docker-compose.logging.yaml \
  --profile storage --profile logging up -d
```
