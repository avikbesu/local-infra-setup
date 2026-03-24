# WireMock Stub Guide

Mock HTTP endpoints for local development and DAG integration testing.

---

## Quick Start

```bash
# Start WireMock alongside the pipeline stack
make mock

# Or standalone
docker compose --profile mock up -d wiremock

# Check it's running
curl http://localhost:8090/__admin/health

# List all loaded stubs
curl http://localhost:8090/__admin/mappings
```

---

## Directory Layout

```
config/wiremock/
├── mappings/                  ← YAML stub definitions (one file per domain)
│   ├── users.yaml
│   ├── pipeline-events.yaml
│   └── catalog-api.yaml
└── __files/                   ← Large response bodies referenced by stubs
    └── catalog-summary.json
```

---

## Adding a New Stub

Create a YAML file in `config/wiremock/mappings/`. Name it after the domain (e.g., `payments.yaml`). Each file can hold multiple stubs under the `mappings:` key.

### Minimal example

```yaml
mappings:
  - name: "GET /api/orders — list"
    request:
      method: GET
      url: /api/orders
    response:
      status: 200
      headers:
        Content-Type: application/json
      jsonBody:
        orders: []
        total: 0
```

### Hot-reload (no restart needed)

```bash
make mock-reload
# or directly:
curl -X POST http://localhost:8090/__admin/mappings/reset
```

---

## Stub Fields Reference

### `request` — matching rules

| Field | Example | Notes |
|---|---|---|
| `method` | `GET`, `POST`, `ANY` | HTTP verb |
| `url` | `/api/users` | Exact path + query match |
| `urlPath` | `/api/users` | Path only, ignores query string |
| `urlPathPattern` | `/api/users/([0-9]+)` | Java regex on path |
| `urlPattern` | `/api/users\?.*` | Java regex on full URL |
| `headers` | see below | Match on request headers |
| `queryParameters` | see below | Match on query params |
| `bodyPatterns` | see below | Match on request body |

#### Header / query matching operators

```yaml
request:
  headers:
    Authorization:
      contains: Bearer          # substring match
    Content-Type:
      equalTo: application/json # exact match
    X-Version:
      matches: "v[0-9]+"        # regex
    X-Debug:
      absent: true              # header must not be present
  queryParameters:
    status:
      equalTo: active
```

#### Request body matching

```yaml
request:
  bodyPatterns:
    - equalToJson: '{"type": "order"}'
    - matchesJsonPath: "$.items[?(@.qty > 0)]"
    - contains: "urgent"
```

### `response` — what to return

| Field | Example | Notes |
|---|---|---|
| `status` | `200` | HTTP status code |
| `headers` | `Content-Type: application/json` | Response headers map |
| `jsonBody` | YAML object | Serialised as JSON automatically |
| `body` | `"plain string"` | Raw body string (supports templates) |
| `bodyFileName` | `orders/list.json` | Path relative to `__files/` |
| `fixedDelayMilliseconds` | `2000` | Add latency to every response |
| `fault` | `CONNECTION_RESET_BY_PEER` | Simulate network faults |

### `priority` — disambiguation

When multiple stubs match the same request, the one with the **lowest numeric priority wins** (default: 5).

```yaml
- name: "catch-all GET /api/orders"
  priority: 10          # lowest priority — fallback
  request:
    method: GET
    urlPath: /api/orders
  response:
    status: 200
    jsonBody: { orders: [] }

- name: "GET /api/orders?status=urgent — override"
  priority: 2           # wins when ?status=urgent is present
  request:
    method: GET
    urlPath: /api/orders
    queryParameters:
      status:
        equalTo: urgent
  response:
    status: 200
    jsonBody: { orders: [{ id: 99, priority: urgent }] }
```

---

## Response Templating

WireMock runs with `--global-response-templating`, so Handlebars expressions work in any `body` string.

```yaml
response:
  body: >
    {
      "echo_path": "{{request.path}}",
      "echo_method": "{{request.method}}",
      "id": "{{request.pathSegments.[2]}}",
      "query_status": "{{request.query.status}}",
      "random_id": "{{randomValue type='UUID'}}",
      "timestamp": "{{now format='yyyy-MM-dd\\'T\\'HH:mm:ss\\'Z\\''}}"
    }
```

Common helpers:

| Helper | Output |
|---|---|
| `{{request.path}}` | `/api/users/42` |
| `{{request.pathSegments.[N]}}` | N-th segment (0-indexed) |
| `{{request.query.key}}` | Query param value |
| `{{request.headers.Authorization}}` | Request header value |
| `{{randomValue type='UUID'}}` | Random UUID |
| `{{randomValue type='ALPHANUMERIC' length=8}}` | Random 8-char string |
| `{{now format='yyyy-MM-dd'}}` | Current date |

---

## Scenario Stubs (Stateful)

Use `scenarioName` to model state transitions (e.g., pending → processing → done):

```yaml
mappings:
  - name: "GET /job/1 — pending (initial state)"
    scenarioName: job-1-lifecycle
    requiredScenarioState: Started        # built-in initial state
    newScenarioState: processing
    request:
      method: GET
      url: /job/1
    response:
      status: 200
      jsonBody: { status: pending }

  - name: "GET /job/1 — processing"
    scenarioName: job-1-lifecycle
    requiredScenarioState: processing
    newScenarioState: done
    request:
      method: GET
      url: /job/1
    response:
      status: 200
      jsonBody: { status: processing }

  - name: "GET /job/1 — done"
    scenarioName: job-1-lifecycle
    requiredScenarioState: done
    request:
      method: GET
      url: /job/1
    response:
      status: 200
      jsonBody: { status: done, result: "ok" }
```

Reset scenario state via Admin API:
```bash
curl -X POST http://localhost:8090/__admin/scenarios/reset
```

---

## Admin API Cheatsheet

```bash
BASE=http://localhost:8090/__admin

# List all loaded stubs
curl $BASE/mappings | python3 -m json.tool

# Reload stubs from disk (after adding/editing files)
curl -X POST $BASE/mappings/reset

# View recent request log
curl $BASE/requests | python3 -m json.tool

# Clear request log
curl -X DELETE $BASE/requests

# Reset all scenario states
curl -X POST $BASE/scenarios/reset

# Check health
curl $BASE/health
```

---

## Tips

- **One file per upstream service** keeps things easy to find (e.g., `payments.yaml`, `auth.yaml`).
- **Use `name:`** on every stub — it shows up in the Admin UI and request logs.
- **Use `X-Mock-Scenario` headers** as a convention to switch between happy-path and failure stubs without changing the URL (see `pipeline-events.yaml` for an example).
- **Extract large bodies** to `__files/` so YAML mapping files stay readable.
- **Avoid `url:` for paths with dynamic segments** — use `urlPathPattern:` with a regex instead.