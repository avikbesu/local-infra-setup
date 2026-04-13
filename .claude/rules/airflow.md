---
paths:
  - "compose/docker-compose.airflow*"
  - "config/airflow*"
  - "config/secrets.yaml"
---

# Airflow 3 Rules

## Import Namespace

Always use the Airflow 3 SDK namespace:

```python
from airflow.sdk import DAG, dag, task, asset
```

Never use the legacy import:
```python
from airflow import DAG  # WRONG — breaks on Airflow 3
```

## Health Check Endpoint

The correct health endpoint is:
```
GET /api/v2/monitor/health
```
Not `/health` (that is the Airflow 2 path).

## Environment Variables

| Variable | Correct | Wrong |
|---|---|---|
| JWT secret | `AIRFLOW__API_AUTH__JWT_SECRET` | `AIRFLOW__API__JWT_SECRET` |
| Execution API | `AIRFLOW__CORE__EXECUTION_API_SERVER_URL` | — |

The scheduler requires `AIRFLOW__CORE__EXECUTION_API_SERVER_URL` to reach `airflow-api-server`.

## DAGs Submodule

The `dags/` directory is a **git submodule**. Never edit files there directly. All DAG changes must go through the upstream DAGs repository.
