# Local Infrastructure Setup

A modular Docker Compose–based local data engineering platform covering object storage, distributed SQL, workflow orchestration, and centralised log shipping.


- [Local Infrastructure Setup](#local-infrastructure-setup)
  - [Overview](#overview)
  - [Quick Start](#quick-start)
    - [Setup](#setup)
    - [Git Submodule Guide](#git-submodule-guide)
  - [Docker Compose](#docker-compose)
    - [Container Dependency Diagram](#container-dependency-diagram)
    - [Compose Files](#compose-files)
    - [Quick Start](#quick-start-1)

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

## Quick Start

### Setup

```bash
git clone --recurse-submodules https://github.com/avikbesu/local-infra-setup.git
```

This auto-creates .gitmodules at repo root. After running, your structure will be:
```
local-infra-setup/
├── dags/                          ← submodule (airflow3-by-example)
│   └── example/
│       └── dags/                  ← actual DAGs folder mounted into Airflow
│           ├── a_basics/
│           ├── b_taskflow/
│           ├── c_operators/
│           ├── d_dynamic_workflows/
│           ├── example_dag.py
│           └── example_taskflow.py
├── compose/
│   └── docker-compose.pipeline.yaml
└── .gitmodules                    ← auto-created
```

### Git Submodule Guide

<details>
<summary> Git Submodule Use Cases</summary>

  1. *Add new submodule at a specified path*
        ```bash
        # Add airflow3-by-example as a submodule at path `dags/`
        git submodule add -b main git@github.com:avikbesu/airflow3-by-example.git dags
        git submodule update --init --recursive
        ```
  2. *Keep only dags folder*
        ```bash
        cd dags
        git sparse-checkout init --cone
        git sparse-checkout set  example/dags
        ```
  3. *Pull latest changes for a git submodule*
        ```bash
        # Pull latest DAGs from airflow3-by-example after updates
        git submodule update --remote dags
        ```
  4. **[Advanced Usage]**:*changes in dags folder and push the changes to remote repo* 
        ```bash
        cd dags
        git checkout main
        git pull origin main
        # perform changes and commit them.
        git push origin main
        ```

</details>






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
        postgres_init["postgres-init\none-shot DB provisioner"]
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

    postgres       -- "healthy"    --> postgres_init
    postgres       -- "healthy"    --> airflow_init
    postgres       -- "healthy"    --> airflow_scheduler
    postgres       -- "healthy"    --> airflow_api

    postgres_init  -- "completed"  --> iceberg_rest
    minio_init     -- "completed"  --> iceberg_rest
    iceberg_rest   -- "healthy"    --> trino

    airflow_init   -- "completed"  --> airflow_scheduler
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
| `docker-compose.storage.yaml` | `storage`, `pipeline` | `minio`, `minio-init` |
| `docker-compose.db.yaml` | `db`, `pipeline`, `query` | `postgres`, `postgres-init` |
| `docker-compose.logging.yaml` | `logging`, `pipeline` | `fluentd` |
| `docker-compose.query.yaml` | `query` | `iceberg-rest`, `trino` |
| `docker-compose.pipeline.yaml` | `pipeline` | `airflow-init`, `airflow-scheduler`, `airflow-api-server` |

### Quick Start

```bash
# Full pipeline stack (storage + db + logging + airflow + trino + iceberg-rest)
make up

# Query engine stack only (Trino + Iceberg REST + Postgres + MinIO)
make query

# Airflow only 
make pipeline
# or 
make up PROFILE=pipeline


```