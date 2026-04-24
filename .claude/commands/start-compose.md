Start one or more Docker Compose profiles, wait for services to become healthy, then report status and exposed ports.

**Rule: never run `docker compose` directly — always go through `make` targets.**

## Arguments

`$ARGUMENTS` may be:
- Empty — start **all** profiles (`db storage logging pipeline query mock proxy`)
- One or more profile names, space- or comma-separated — e.g. `db storage` or `pipeline,db`

Valid profiles: `db` · `storage` · `logging` · `pipeline` · `query` · `mock` · `proxy`

Profile dependencies (start these together or services will fail):
- `pipeline` requires `db`
- `query` requires `db` and `storage`
- `logging` requires `storage`
- `proxy` has no hard requirements but is most useful alongside `pipeline` and/or `query`

---

## Steps

### 1. Parse profiles

If `$ARGUMENTS` is empty, use all profiles:
```
db storage logging pipeline query mock proxy
```

Otherwise normalise `$ARGUMENTS`: replace commas with spaces, trim whitespace, split into a list.

Validate each profile name against the known set. If an unknown profile is given, tell the user and stop.

### 2. Ensure prerequisites

Check `.env.local` exists:
```bash
[[ -f .env.local ]] || { echo "❌ .env.local not found — run: make secrets"; exit 1; }
```

For `pipeline` or `query` profiles, ensure airflow dirs exist:
```bash
make airflow-dirs --no-print-directory
```

### 3. Start the stack

Use `make up` with `PROFILE` set to a comma-joined list of the requested profiles:

```bash
make up PROFILE=<comma-joined-profiles>
```

Examples:
- `make up PROFILE=pipeline,db`
- `make up PROFILE=db,storage,query`
- `make up PROFILE=db,storage,logging,pipeline,query,mock,proxy`

`make up` handles env file loading, compose file globbing, and `docker compose up -d --remove-orphans` internally.

If `make up` exits non-zero, stop and report the error — do not proceed to health checks.

### 4. Health check — wait for services to become healthy

Poll service health using `make ps` output (which calls `docker compose ps`). For precise per-container health, use `docker inspect` directly — this is a read-only status check, not a compose operation, so it is allowed:

```bash
DEADLINE=$(($(date +%s) + 180))   # 3-minute overall timeout

while [[ $(date +%s) -lt $DEADLINE ]]; do
  ALL_READY=true
  for cid in $(docker ps -q --filter "label=com.docker.compose.project"); do
    health=$(docker inspect --format='{{.State.Health.Status}}' "$cid" 2>/dev/null || echo "none")
    [[ "$health" == "starting" ]] && ALL_READY=false
  done
  $ALL_READY && break
  sleep 5
done
```

For each running container associated with the started profiles, determine final status:
- `healthy` → ✅
- `unhealthy` → ❌ (collect for error report)
- `none` / no healthcheck defined → check exit code: exited 0 = ⚪ success, exited non-zero = ❌
- `starting` after timeout → ❌

### 5. Check for startup errors in logs

For any service that is `unhealthy` or exited non-zero, fetch its recent logs using make:
```bash
make logs SERVICE=<name> 2>&1 | tail -30
```

Extract key error lines (grep for `ERROR`, `Exception`, `Fatal`, `error`, `failed`). Do not dump the full log.

### 6. Report status and ports

Get container state with:
```bash
docker ps -a --format '{{json .}}' | python3 -c "
import sys, json
for line in sys.stdin:
    c = json.loads(line)
    print(c['Names'], c['Status'], c['Ports'])
"
```

Print a status table:

```
Service              Status              Ports
──────────────────────────────────────────────────────────────
postgres             ✅ healthy          localhost:5432
airflow-api-server   ✅ healthy          localhost:8080  → Airflow UI: http://localhost:8080
airflow-scheduler    ✅ healthy
airflow-init         ⚪ exited(0)        (one-shot — completed successfully)
```

Only show ports where a host port is published. Add friendly URL labels for well-known services:
- `airflow-api-server` port 8080 → `Airflow UI: http://localhost:8080`
- `minio` port 9001 → `MinIO Console: http://localhost:9001`
- `minio` port 9000 → `MinIO S3 API: http://localhost:9000`
- `trino` port 8080 → `Trino UI: http://localhost:8080`
- `wiremock` → `WireMock Admin: http://localhost:<port>/__admin/`
- `nginx` port 80 → `Proxy: http://localhost:80`
- `postgres` port 5432 → `Postgres: localhost:5432`

### 7. Final summary

End with one of:
- `✅ Stack is up — all services healthy`
- `⚠️  Stack is up but N service(s) need attention:` followed by service names and extracted error lines

If any service is unhealthy, suggest:
```
Tail logs:    make logs SERVICE=<name>
Full restart: make down && make up PROFILE=<profiles>
```
