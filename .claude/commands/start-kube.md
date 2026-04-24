Start one or more Helm components on the local kind cluster, wait for all pods to become ready, start port-forwards, then report release status, pod health, and exposed endpoints.

**Rule: never run `helm`, `kubectl`, or `kind` directly — always go through `make` targets.**

## Arguments

`$ARGUMENTS` may be:
- Empty — deploy **all enabled** components in dependency order
- One or more component names, space- or comma-separated — e.g. `postgres` or `postgres,airflow`

Valid component names (from `cluster/helm-components.yaml`):
- `postgres`  — depends on: nothing
- `airflow`   — depends on: `postgres`
- `wiremock`  — depends on: nothing
- `nginx`     — depends on: `airflow`, `wiremock`
- `minio`     — disabled by default; enable in `cluster/helm-components.yaml` first

Dependency rules — warn and stop if a dependency is missing:
- `airflow` requires `postgres`
- `nginx` requires `airflow` and `wiremock`

---

## Steps

### 1. Parse components

If `$ARGUMENTS` is empty, use the "all" path (step 3a).

Otherwise normalise `$ARGUMENTS`: replace commas with spaces, trim whitespace, split into a list.

Validate each name against the known component list. If an unknown name is given, tell the user and stop.

For named components, check that required dependencies are included in the list or already deployed:
```bash
make kube-status 2>/dev/null | grep -E "● <dep>"
```
Warn if a dependency appears as `not-installed`.

### 2. Ensure prerequisites

Check `.env.local` exists:
```bash
[[ -f .env.local ]] || { echo "❌ .env.local not found — run: make secrets"; exit 1; }
```

Ensure the kind cluster exists (idempotent):
```bash
make kube-start --no-print-directory
```

Ensure Helm repos are registered and secrets are applied:
```bash
make helm-repos --no-print-directory
make kube-secrets --no-print-directory
```

### 3. Deploy components

**All components (no arguments given):**
```bash
make kube-deploy
```

**Specific component(s):** deploy each in the order provided:
```bash
make kube-deploy-one COMPONENT=<name>
```

`kube-deploy` and `kube-deploy-one` use `helm upgrade --install --atomic --wait` internally — they block until the Helm release is fully ready or roll back on failure. If either exits non-zero, stop immediately and report the error. Do not continue to the next component.

### 4. Health check — wait for pods to become Running/Ready

After deployment, poll pod readiness using the new `kube-health` target:

**All components:**
```bash
make kube-health
```

**Single component:**
```bash
make kube-health COMPONENT=<name>
```

`kube-health` polls every 5 seconds up to 300 seconds and exits non-zero if any pod is not Ready. It also surfaces pod events and log error lines for any failing pod.

If `make kube-health` exits non-zero, report the failure output. Do not start port-forwards for components that failed health checks.

### 5. Start port-forwards

Once all targeted components are healthy, start background port-forwards:
```bash
make kube-port-forward
```

Then show what is forwarding:
```bash
make kube-port-forward-status
```

### 6. Report status and ports

Run `make kube-status` to get the full picture, then summarise it as a table:

```
Component   Namespace  Helm Release   Pod Health     Port-Forwards
─────────────────────────────────────────────────────────────────────────────
postgres    db         ✅ deployed    1/1 Ready       localhost:5432
airflow     af         ✅ deployed    4/4 Ready       localhost:8080
wiremock    misc       ✅ deployed    1/1 Ready       localhost:8090
nginx       misc       ✅ deployed    1/1 Ready       localhost:8080
```

Helm status symbols:
- `deployed`      → ✅
- `pending-*`     → ⏳
- `failed`        → ❌
- `not-installed` → ○

Port-forward friendly URL labels:
- airflow 8080   → `Airflow UI:      http://localhost:8080`
- minio 9001     → `MinIO Console:   http://localhost:9001`
- minio 9000     → `MinIO S3 API:    http://localhost:9000`
- wiremock 8090  → `WireMock Admin:  http://localhost:8090/__admin/`
- nginx 8080     → `Proxy:           http://localhost:8080`
- postgres 5432  → `Postgres:        localhost:5432`

### 7. Final summary

End with one of:
- `✅ Kube stack is up — all components deployed and pods healthy`
- `⚠️  Kube stack is up but N component(s) need attention:` followed by component names and the health/log output from step 4

If any component is failing, suggest:
```
Tail logs:      make kube-logs COMPONENT=<name>
Previous crash: make kube-logs COMPONENT=<name> FLAG=--previous
Live stream:    make kube-logs COMPONENT=<name> FLAG=--follow
Full status:    make kube-status
Redeploy:       make kube-remove-one COMPONENT=<name> && make kube-deploy-one COMPONENT=<name>
```
