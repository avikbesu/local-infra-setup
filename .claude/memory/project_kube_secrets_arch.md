---
name: Kubernetes secrets architecture
description: How K8s Secrets are managed for the postgres and airflow Helm deployments
type: project
---

K8s Secrets are created by `make kube-secrets` (runs `scripts/kube-secrets.sh`) before any Helm deploy. `kube-deploy` and `kube-deploy-one` both depend on `kube-secrets` as a Make prerequisite.

**Why:** Values files must not contain real credentials. Secrets come from `.env.local` via the script, keeping the pattern consistent with Docker Compose.

**How to apply:** When adding new secrets for K8s workloads, add them to `scripts/kube-secrets.sh` (not to `helm/*/values.yaml`). Add the key to `config/secrets.yaml` if a new generated secret is needed.

Namespaces: `db` (postgres), `af` (airflow), `s3` (minio), `misc` (nginx + wiremock)

Secrets created:
- `db/postgres-credentials` — Bitnami PostgreSQL `existingSecret` (keys: `password`, `postgres-password`)
- `af/airflow-metadata` — full SQLAlchemy URI (key: `connection`)
- `af/airflow-webserver` — webserver/API/JWT secret key (key: `webserver-secret-key`)
- `af/airflow-fernet` — Fernet key (key: `fernet-key`)
- `s3/minio-credentials` — MinIO Helm `existingSecret` (keys: `rootUser`, `rootPassword`)

ConfigMaps created:
- `misc/wiremock-stubs` — built from `compose/wiremock/mappings/` via `kubectl create configmap --from-file`; reload with `make kube-stubs-reload`

ResourceQuotas applied per namespace: `db`, `af`, `misc`, `s3` (CPU/memory/pod limits for single-node kind).

Postgres cross-namespace FQDN: `postgres-postgresql.db.svc.cluster.local:5432`
(Bitnami release=`postgres`, chart=`postgresql` → service name = `postgres-postgresql`)
