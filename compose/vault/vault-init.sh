#!/bin/sh
# vault-init.sh — watch-and-seed sidecar for the vault dev-mode container.
#
# Dev mode uses an in-memory backend: all data is lost on every vault restart.
# This script runs as a sidecar (restart: unless-stopped) and re-seeds policies,
# the Airflow scoped token, and example secrets each time vault comes back up.
#
# Required env vars (set in docker-compose.vault.yaml):
#   VAULT_ADDR           — e.g. http://vault:8200
#   VAULT_TOKEN          — root token (VAULT_DEV_ROOT_TOKEN) for seeding only
#   VAULT_AIRFLOW_TOKEN  — hex token ID to create for Airflow's VaultBackend
#   POSTGRES_USER        — seeded into connections/postgres_default
#   POSTGRES_PASSWORD    — seeded into connections/postgres_default
#   POSTGRES_DB          — seeded into connections/postgres_default
set -eu

POLL_INTERVAL=30   # seconds between health polls after seeding

wait_for_vault() {
  echo "[vault-init] Waiting for Vault to be ready..."
  until vault status -address="${VAULT_ADDR}" >/dev/null 2>&1; do
    sleep 2
  done
  echo "[vault-init] Vault is ready."
}

seed_vault() {
  echo "[vault-init] Writing airflow-ro policy..."
  vault policy write airflow-ro - <<POLICY
path "secret/data/airflow/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/airflow/*" {
  capabilities = ["list"]
}
POLICY

  # POSIX-compatible prefix (${var:0:8} is bash-only; busybox sh rejects it).
  TOKEN_PREFIX=$(printf '%s' "${VAULT_AIRFLOW_TOKEN}" | cut -c1-8)
  echo "[vault-init] Creating scoped Airflow token (id=${TOKEN_PREFIX}...)..."
  # Idempotent: skip creation if the token already exists.
  # vault-init restarts while Vault is still live would otherwise fail here
  # and crash-loop because set -eu aborts on non-zero exit.
  if ! vault token lookup "${VAULT_AIRFLOW_TOKEN}" >/dev/null 2>&1; then
    vault token create \
      -id="${VAULT_AIRFLOW_TOKEN}" \
      -policy=airflow-ro \
      -no-default-policy \
      -period=72h \
      -display-name=airflow-ro \
      >/dev/null
  else
    echo "[vault-init] Token already exists — skipping create."
  fi

  echo "[vault-init] Seeding connection: postgres_default..."
  vault kv put secret/airflow/connections/postgres_default \
    conn_type=postgres \
    host=postgres \
    schema="${POSTGRES_DB}" \
    login="${POSTGRES_USER}" \
    password="${POSTGRES_PASSWORD}" \
    port=5432

  echo "[vault-init] Seeding variable: environment..."
  vault kv put secret/airflow/variables/environment value=local

  echo "[vault-init] Vault seeding complete."
}

main() {
  wait_for_vault
  seed_vault

  # Poll: detect vault restart (dev mode wipes all state on restart) and re-seed.
  # Also renew the scoped token each cycle so it doesn't expire after -period=72h
  # on long-running stacks where Vault never restarts.
  while true; do
    sleep "${POLL_INTERVAL}"
    if ! vault status -address="${VAULT_ADDR}" >/dev/null 2>&1; then
      echo "[vault-init] Vault became unavailable — waiting for restart..."
      wait_for_vault
      seed_vault
    else
      vault token renew "${VAULT_AIRFLOW_TOKEN}" >/dev/null 2>&1 || true
    fi
  done
}

main
