#!/usr/bin/env bash
# =============================================================================
# scripts/kube-secrets.sh
# Creates Kubernetes Secrets and ConfigMaps required before helm install.
# Idempotent: uses kubectl --dry-run=client | kubectl apply pattern.
#
# Usage:
#   ./scripts/kube-secrets.sh        # called via: make kube-secrets
#
# Secrets created:
#   db/postgres-credentials          — Bitnami PostgreSQL existingSecret
#   af/airflow-metadata              — Airflow metadata DB connection URI
#   af/airflow-webserver             — Airflow webserver/API secret key
#   af/airflow-fernet                — Airflow Fernet encryption key
#
# ConfigMaps created:
#   misc/wiremock-stubs              — WireMock stub mappings from
#                                      compose/wiremock/mappings/ (--from-file)
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/lib/kube-common.sh"

require_kubectl

ENV_LOCAL="${REPO_ROOT}/.env.local"
[[ -f "$ENV_LOCAL" ]] || { log_error ".env.local not found — run: make secrets"; exit 1; }

# Load all secrets into the current shell
set -o allexport
# shellcheck disable=SC1090
source "$ENV_LOCAL"
set +o allexport

log_step "Kube Secrets & ConfigMaps"
log_info "Source: $ENV_LOCAL"

# ── Helper: create or update a generic secret idempotently ────────────────────
create_secret() {
  local ns="$1" name="$2"
  shift 2
  local literal_args=()
  for pair in "$@"; do
    literal_args+=("--from-literal=${pair}")
  done
  kubectl create secret generic "$name" \
    --namespace "$ns" \
    --dry-run=client -o yaml \
    "${literal_args[@]}" \
    | kubectl apply -f -
}

# ── Ensure namespaces exist (idempotent) ──────────────────────────────────────
for ns in db af misc s3; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
  log_info "  namespace/$ns (ensured)"
done

# ── ResourceQuota per namespace ───────────────────────────────────────────────
# Prevents a single component from consuming all node resources.
# Limits are sized for a single-node kind cluster with ~4 vCPU / 6 GB RAM.
apply_quota() {
  local ns="$1" cpu_req="$2" mem_req="$3" cpu_lim="$4" mem_lim="$5" pods="$6"
  kubectl apply -f - <<EOF
apiVersion: v1
kind: ResourceQuota
metadata:
  name: ${ns}-quota
  namespace: ${ns}
spec:
  hard:
    requests.cpu: "${cpu_req}"
    requests.memory: "${mem_req}"
    limits.cpu: "${cpu_lim}"
    limits.memory: "${mem_lim}"
    pods: "${pods}"
EOF
  log_info "  ResourceQuota/${ns}-quota (ensured)"
}

log_step "Namespace ResourceQuotas"
apply_quota db  "200m" "512Mi" "500m" "512Mi" "5"
apply_quota af  "1"    "2Gi"   "3"    "4Gi"   "20"
apply_quota misc "200m" "256Mi" "500m" "512Mi" "10"
apply_quota s3  "100m" "256Mi" "500m" "512Mi" "5"

# ── db/postgres-credentials ───────────────────────────────────────────────────
# Bitnami PostgreSQL chart reads these keys when auth.existingSecret is set:
#   password          → regular user (auth.username)
#   postgres-password → postgres superuser
log_info "  Creating: db/postgres-credentials"
create_secret db postgres-credentials \
  "password=${POSTGRES_PASSWORD}" \
  "postgres-password=${POSTGRES_PASSWORD}"
log_ok "  db/postgres-credentials"

# ── af/airflow-metadata ───────────────────────────────────────────────────────
# Apache Airflow chart expects key `connection` = full SQLAlchemy URI when
# data.metadataSecretName is set. Postgres service FQDN:
#   postgres-postgresql.db.svc.cluster.local  (bitnami release=postgres, chart=postgresql)
METADATA_CONN="postgresql+psycopg2://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres-postgresql.db.svc.cluster.local:5432/${POSTGRES_DB}"
log_info "  Creating: af/airflow-metadata"
create_secret af airflow-metadata \
  "connection=${METADATA_CONN}"
log_ok "  af/airflow-metadata"

# ── af/airflow-webserver ──────────────────────────────────────────────────────
# Apache Airflow chart injects `webserver-secret-key` when
# webserverSecretKeySecretName is set. Same value also used for:
#   AIRFLOW__API__SECRET_KEY, AIRFLOW__API_AUTH__JWT_SECRET,
#   AIRFLOW__CORE__INTERNAL_API_SECRET_KEY  (injected via extraEnv in values.yaml)
log_info "  Creating: af/airflow-webserver"
create_secret af airflow-webserver \
  "webserver-secret-key=${AIRFLOW_SECRET_KEY}"
log_ok "  af/airflow-webserver"

# ── af/airflow-fernet ─────────────────────────────────────────────────────────
# Apache Airflow chart injects `fernet-key` when fernetKeySecretName is set.
log_info "  Creating: af/airflow-fernet"
create_secret af airflow-fernet \
  "fernet-key=${AIRFLOW_FERNET_KEY}"
log_ok "  af/airflow-fernet"

# ── s3/minio-credentials ─────────────────────────────────────────────────────
# MinIO Helm chart reads rootUser / rootPassword from this secret when
# existingSecret is set in helm/minio/values.yaml.
log_info "  Creating: s3/minio-credentials"
create_secret s3 minio-credentials \
  "rootUser=${MINIO_ROOT_USER}" \
  "rootPassword=${MINIO_ROOT_PASSWORD}"
log_ok "  s3/minio-credentials"

# ── misc/wiremock-stubs ───────────────────────────────────────────────────────
# Built dynamically from compose/wiremock/mappings/ so that adding a stub file
# there is enough — no manual YAML editing required.
# Mounted read-only into the WireMock pod at /home/wiremock/mappings.
STUBS_DIR="${REPO_ROOT}/compose/wiremock/mappings"
if [[ -d "$STUBS_DIR" ]] && [[ -n "$(ls -A "$STUBS_DIR" 2>/dev/null)" ]]; then
  log_info "  Creating: misc/wiremock-stubs (from $STUBS_DIR)"
  kubectl create configmap wiremock-stubs \
    --namespace misc \
    --from-file="$STUBS_DIR" \
    --dry-run=client -o yaml \
    | kubectl apply -f -
  log_ok "  misc/wiremock-stubs ($(ls "$STUBS_DIR" | wc -l | tr -d ' ') stub file(s))"
else
  log_warn "  Skipping wiremock-stubs: no files found in $STUBS_DIR"
fi

echo ""
log_ok "All secrets and ConfigMaps applied in namespaces: db, af, misc, s3."
log_info "  Next: make kube-deploy"
log_info "  To reload stubs live: make kube-stubs-reload"
