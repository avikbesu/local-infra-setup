# Gaps Found in Analysis — Now Tracked as GitHub Issues

Last reviewed: 2026-04-23. All gaps promoted to GitHub issues on 2026-04-23.

| Gap | GitHub Issue |
|-----|-------------|
| GAP-C1: minio-init bucket loop fragility | #48 |
| GAP-C2: postgres-init pipeline profile undocumented | #49 |
| GAP-C3: Nginx compose missing resource limits | #47 |
| GAP-C5: airflow-init silent failure on user creation | #45 |
| GAP-C7: Nginx compose missing depends_on | #46 |
| GAP-K2: Nginx Helm routes to disabled MinIO (502) | #50 |
| GAP-K3: kube-secrets.sh doesn't handle MinIO enablement | #51 |
| GAP-K4: Airflow logs not persisted in K8s | #52 |
| GAP-K7: Makefile help text stale ENV reference | #53 |
| GAP-K8: Airflow probe tuning inconsistency | #54 |
| GAP-S2: cluster/install.sh missing error handling | #55 |

Gaps covered by existing issues (not duplicated above):
- GAP-C4 (fluentd :latest) → #30
- GAP-C6 (WireMock compose resource limits) → #23
- GAP-K1 (MinIO hardcoded password in Helm) → #3
- GAP-K5 (no image digest) → #17
- GAP-K6 (postgres disabled without docs) → #36
- GAP-S1 (postgres setup.sh set -euo pipefail) → #20

---

---

## Docker Compose Gaps

### GAP-C1: `minio-init` entrypoint uses `$(ls ...)` variable expansion
**File:** `compose/docker-compose.storage.yaml`
**Problem:** The `minio-init` entrypoint uses `$$(echo $$MINIO_BUCKETS | tr ',' ' ')` which is correct for compose variable escaping, but the outer `for bucket in ...` loop will silently skip buckets with spaces in names. Lower risk since bucket names are controlled, but pattern is fragile.

### GAP-C2: `postgres-init` not included in `pipeline` profile
**File:** `compose/docker-compose.db.yaml`
```yaml
postgres-init:
  profiles:
    - "db"
    # - "pipeline"   ← commented out
```
**Problem:** If someone starts only `--profile pipeline` (not `--profile db`), `postgres-init` doesn't run. Airflow works (uses `airflow` DB), but the `iceberg` database won't be created if they later add `--profile query`. The comment suggests this is intentional but it's undocumented behaviour.
**Recommendation:** Add a comment explaining why `pipeline` is excluded.

### GAP-C3: Nginx compose has no resource limits
**File:** `compose/docker-compose.proxy.yaml`
**Problem:** The nginx service has no `deploy.resources` block (unlike postgres, minio, and airflow which all have limits). Tracked partly by #6/#33 but nginx specifically is not mentioned.

### GAP-C4: Fluentd built image tag `fluentd-local:latest`
**File:** `compose/docker-compose.logging.yaml`
```yaml
image: fluentd-local:latest      # cached after first build
```
**Problem:** The image is always tagged `:latest` regardless of what changed in `compose/fluentd/`. Two developers building from different states of the Dockerfile get the same tag — Docker layer cache may serve a stale image. Consider tagging with a digest or content hash.

### GAP-C5: `airflow-init` always recreates admin user (silent no-op `|| true`)
**File:** `compose/docker-compose.pipeline.yaml`
```bash
airflow users create ... || true
```
**Problem:** The `|| true` means if `airflow db migrate` succeeds but user creation fails for a non-"already exists" reason (wrong env var, DB issue), the container still exits 0. `airflow-scheduler` then starts against a broken state. Consider replacing with explicit `if airflow users list | grep -q "$AIRFLOW_ADMIN_USER"; then ... fi` guard.

### GAP-C6: WireMock compose missing resource limits
**File:** `compose/docker-compose.mock.yaml`
**Problem:** No `deploy.resources` block. Tracked by #23 but worth noting specifically — the helm values already have limits; compose doesn't.

### GAP-C7: Nginx depends_on not set in compose
**File:** `compose/docker-compose.proxy.yaml`
**Problem:** Nginx has no `depends_on` in compose. It will start before airflow/wiremock, and since it uses static `proxy_pass` (not `set $upstream`), nginx will fail to resolve upstreams at startup if they're not yet running. May cause intermittent 502s on fresh stack bring-up.

---

## Helm / Kubernetes Gaps

### GAP-K1: `helm/minio/values.yaml` has hardcoded `rootPassword: "minio123"`
**File:** `helm/minio/values.yaml`
```yaml
rootUser: "minio"
rootPassword: "minio123"
```
**Problem:** MinIO is `enabled: false` in `cluster/helm-components.yaml` so it's not deployed, but if someone enables it, the hardcoded credential deploys immediately. Covered by issue #3 but listed here for completeness.
**Fix:** Add `s3/minio-credentials` to `kube-secrets.sh`; reference from values via `existingSecret`.

### GAP-K2: Nginx Helm routes `/minio/` and `/minio-api/` point to disabled MinIO
**File:** `helm/nginx/values.yaml`
**Problem:** Nginx is deployed (`enabled: true`) but its `serverBlock` includes routes to `minio-console.s3.svc.cluster.local:9001` and `minio.s3.svc.cluster.local:9000`, which don't exist (MinIO is disabled). Nginx starts fine (upstreams resolved lazily), but `/minio/` requests return 502. Should either remove those routes or document the dependency.

### GAP-K3: `kube-secrets.sh` does not create `s3` namespace or MinIO secrets
**File:** `scripts/kube-secrets.sh`
**Problem:** Script creates `db`, `af`, `misc` namespaces. If MinIO is ever enabled, it deploys to namespace `s3` which won't be pre-created, and there are no MinIO secrets. Enabling MinIO requires manual steps not documented anywhere.

### GAP-K4: Airflow log persistence disabled — logs ephemeral
**File:** `helm/airflow/values.yaml`
```yaml
logs:
  persistence:
    enabled: false
logGroomer:
  enabled: false
```
**Problem:** Task logs are lost when pods restart. Acceptable for local dev but should be documented. `logGroomer` is disabled but there's nothing cleaning up ephemeral logs either.

### GAP-K5: No `defaultAirflowDigest` — image integrity not verified
**File:** `helm/airflow/values.yaml`
```yaml
defaultAirflowDigest: ""
```
**Problem:** Tag alone doesn't guarantee the same image across pulls. Digest pinning would prevent supply-chain substitution attacks. Low risk for local dev, but worth noting.

### GAP-K6: `postgres` is `enabled: false` in `helm-components.yaml` without explanation
**File:** `cluster/helm-components.yaml`
**Problem:** Postgres component exists in the registry but is disabled. It's unclear if this is intentional (use compose postgres instead) or an oversight. This is tracked by issue #36 (docs).

### GAP-K7: Makefile help text still mentions `[ENV=dev|prod|ci]` after ENV removal
**File:** `makefile`
```makefile
@echo "  Usage: make <target> [USE_KIND=true] [ENV=dev|prod|ci]"
```
**Problem:** Issue #40 (CLOSED) was about removing the `ENV` variable, which was done. But the help text still advertises it, creating confusion. One-line fix.

### GAP-K8: Airflow `dagProcessor` missing `livenessProbe.timeoutSeconds` tuning consistency
**File:** `helm/airflow/values.yaml`
**Problem:** `triggerer` has detailed liveness probe tuning with comments explaining the reasoning (slow `airflow jobs check` command). `dagProcessor` has the same values but without the explanatory comment, and `scheduler` has different values. The inconsistency may cause probe failures on resource-constrained nodes.

---

## Script Gaps

### GAP-S1: `config/postgres/setup.sh` missing `set -euo pipefail` and uses `$(ls ...)` anti-pattern
**File:** `config/postgres/setup.sh`
**Problem:** No error handling header. Uses `for f in $(ls /opt/init/sql/*.sql)` — breaks on filenames with spaces, doesn't fail on ls error. This is the specific case called out in issue #20 which is otherwise resolved.
**Fix:**
```bash
#!/usr/bin/env bash
set -euo pipefail
for f in /opt/init/sql/*.sql; do
  [ -f "$f" ] || continue
  echo "▶  running $f"
  psql -h postgres -U "${POSTGRES_USER}" -f "$f"
  echo "✔  $f done"
done
echo "postgres-init complete."
```

### GAP-S2: `cluster/install.sh` has no shebang and no `set -euo pipefail`
**File:** `cluster/install.sh`
**Problem:** Install script for kind setup is a comment-only file (no executable content based on first lines). If it's meant to be runnable, it needs proper error handling.

---

## Positive Findings (Things Done Well)

- All `scripts/*.sh` have `set -euo pipefail` ✓
- All helm services have `resources.limits` and `resources.requests` ✓
- Airflow helm values use `fernetKeySecretName` + `webserverSecretKeySecretName` — no secrets in values.yaml ✓
- Postgres helm values use `auth.existingSecret` ✓
- `kube-secrets.sh` is idempotent (`--dry-run=client | kubectl apply`) ✓
- `migrateDatabaseJob.useHelmHooks: false` prevents Helm hook race conditions ✓
- All compose stateful services have `healthcheck` blocks ✓
- All `depends_on` in compose use `condition:` key ✓
- `minio-init` and `postgres-init` are one-shot `restart: no` containers ✓
- Airflow triggerer probe timeouts properly tuned with explanatory comments ✓
