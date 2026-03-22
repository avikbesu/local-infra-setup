# =============================================================================
##@ Query — Trino SQL  +  Iceberg REST API
#
# Every Trino target has a paired Iceberg REST equivalent comment showing
# the equivalent operation via the catalog HTTP API.
#
# Variables (all overridable on the command line):
#   CATALOG   — Trino catalog name           (default: iceberg)
#   SCHEMA    — Trino schema / Iceberg namespace (default: default)
#   TABLE     — Table name                   (required by describe/select/meta)
#   SQL       — Raw SQL string               (required by trino-query)
#   LIMIT     — Row cap for trino-select     (default: 20)
#   NAMESPACE — Iceberg namespace for REST targets (default: mirrors SCHEMA)
#
# Examples:
#   make trino-schemas
#   make trino-tables SCHEMA=my_schema
#   make trino-describe TABLE=events SCHEMA=my_schema
#   make trino-select  TABLE=events  SCHEMA=my_schema  LIMIT=50
#   make trino-query   SQL="SELECT count(*) FROM iceberg.my_schema.events"
#
#   make iceberg-namespaces
#   make iceberg-tables   NAMESPACE=my_schema
#   make iceberg-table-meta  NAMESPACE=my_schema  TABLE=events
#   make iceberg-snapshots   NAMESPACE=my_schema  TABLE=events
# =============================================================================

# ── Query variables ───────────────────────────────────────────────────────────
CATALOG   ?= iceberg
SCHEMA    ?= default
TABLE     ?=
SQL       ?=
LIMIT     ?= 20
NAMESPACE ?= $(SCHEMA)    # mirrors SCHEMA so you only need to set one

# Read ports from .env (same pattern used for ICEBERG_REST_VERSION above).
# Falls back to .env defaults if the variable is absent.
_TRINO_PORT        := $(strip $(shell grep -s '^TRINO_PORT='        .env | cut -d= -f2))
_TRINO_PORT        := $(if $(_TRINO_PORT),$(_TRINO_PORT),8080)
_ICEBERG_REST_PORT := $(strip $(shell grep -s '^ICEBERG_REST_PORT=' .env | cut -d= -f2))
_ICEBERG_REST_PORT := $(if $(_ICEBERG_REST_PORT),$(_ICEBERG_REST_PORT),8181)

# Trino CLI inside the container always talks to its own loopback.
_TRINO_SERVER := http://localhost:8080

# Shared exec prefix — non-interactive for scripted targets.
_TRINO_EXEC  := docker exec trino trino --server $(_TRINO_SERVER)
# Interactive version used only for trino-shell.
_TRINO_EXEC_IT := docker exec -it trino trino --server $(_TRINO_SERVER)

.PHONY: trino-shell trino-schemas trino-tables trino-describe trino-select trino-query \
        iceberg-namespaces iceberg-tables iceberg-table-meta iceberg-snapshots

# =============================================================================
# Trino targets
# =============================================================================

trino-shell: ## Interactive Trino CLI  [CATALOG=iceberg] [SCHEMA=default]
	@echo "🔍  Connecting to Trino → localhost:$(_TRINO_PORT)  (catalog=$(CATALOG) schema=$(SCHEMA))"
	@echo "    Type 'help;' for usage, 'quit;' to exit."
	@echo ""
	$(_TRINO_EXEC_IT) \
	  --catalog $(CATALOG) \
	  --schema  $(SCHEMA)

# Equivalent Iceberg REST: GET /v1/namespaces
trino-schemas: ## List all schemas in a catalog  [CATALOG=iceberg]
	@echo "📋  SHOW SCHEMAS  in catalog '$(CATALOG)':"
	@echo ""
	$(_TRINO_EXEC) \
	  --catalog $(CATALOG) \
	  --execute "SHOW SCHEMAS" \
	  --output-format ALIGNED

# Equivalent Iceberg REST: GET /v1/namespaces/{namespace}/tables
trino-tables: ## List tables in a schema  [CATALOG=iceberg] [SCHEMA=default]
	@echo "📋  SHOW TABLES  in $(CATALOG).$(SCHEMA):"
	@echo ""
	$(_TRINO_EXEC) \
	  --catalog $(CATALOG) \
	  --schema  $(SCHEMA) \
	  --execute "SHOW TABLES" \
	  --output-format ALIGNED

# Equivalent Iceberg REST: GET /v1/namespaces/{namespace}/tables/{table}
#                          → metadata.schema.fields[]
trino-describe: ## Describe a table  TABLE=<name> [CATALOG=iceberg] [SCHEMA=default]
	@[[ -n "$(TABLE)" ]] || { \
	  echo "❌  TABLE is required."; \
	  echo "    Usage: make trino-describe TABLE=<table> [SCHEMA=default] [CATALOG=iceberg]"; \
	  exit 1; }
	@echo "📐  DESCRIBE $(CATALOG).$(SCHEMA).$(TABLE):"
	@echo ""
	$(_TRINO_EXEC) \
	  --catalog $(CATALOG) \
	  --schema  $(SCHEMA) \
	  --execute "DESCRIBE $(TABLE)" \
	  --output-format ALIGNED

# No direct Iceberg REST equivalent — REST catalog is metadata-only;
# data queries always go through an engine like Trino.
trino-select: ## SELECT * from a table  TABLE=<name> [SCHEMA=default] [LIMIT=20] [CATALOG=iceberg]
	@[[ -n "$(TABLE)" ]] || { \
	  echo "❌  TABLE is required."; \
	  echo "    Usage: make trino-select TABLE=<table> [SCHEMA=default] [LIMIT=20] [CATALOG=iceberg]"; \
	  exit 1; }
	@echo "🔎  SELECT * FROM $(CATALOG).$(SCHEMA).$(TABLE) LIMIT $(LIMIT):"
	@echo ""
	$(_TRINO_EXEC) \
	  --catalog $(CATALOG) \
	  --schema  $(SCHEMA) \
	  --execute "SELECT * FROM $(TABLE) LIMIT $(LIMIT)" \
	  --output-format ALIGNED

trino-query: ## Run arbitrary SQL via Trino  SQL="<query>" [CATALOG=iceberg] [SCHEMA=default]
	@[[ -n "$(SQL)" ]] || { \
	  echo "❌  SQL is required."; \
	  echo "    Usage: make trino-query SQL=\"SELECT count(*) FROM my_table\" [CATALOG=iceberg] [SCHEMA=default]"; \
	  exit 1; }
	$(_TRINO_EXEC) \
	  --catalog $(CATALOG) \
	  --schema  $(SCHEMA) \
	  --execute "$(SQL)" \
	  --output-format ALIGNED

# =============================================================================
# Iceberg REST catalog targets
# These hit the catalog HTTP API directly — useful for metadata inspection
# without starting a query engine session.
# =============================================================================

# Trino SQL equivalent: SHOW SCHEMAS IN iceberg
iceberg-namespaces: ## List Iceberg namespaces via REST  (≡ Trino: SHOW SCHEMAS)
	@echo "📋  GET /v1/namespaces  → localhost:$(_ICEBERG_REST_PORT)"
	@echo ""
	@curl -sf http://localhost:$(_ICEBERG_REST_PORT)/v1/namespaces \
	  | python3 -c "\
import sys, json; \
d = json.load(sys.stdin); \
nss = d.get('namespaces', []); \
print(f'  {len(nss)} namespace(s) found:\n'); \
[print('  •', '.'.join(ns)) for ns in nss]"

# Trino SQL equivalent: SHOW TABLES IN iceberg.<namespace>
iceberg-tables: ## List tables in an Iceberg namespace via REST  [NAMESPACE=default]  (≡ Trino: SHOW TABLES)
	@echo "📋  GET /v1/namespaces/$(NAMESPACE)/tables  → localhost:$(_ICEBERG_REST_PORT)"
	@echo ""
	@curl -sf http://localhost:$(_ICEBERG_REST_PORT)/v1/namespaces/$(NAMESPACE)/tables \
	  | python3 -c "\
import sys, json; \
d = json.load(sys.stdin); \
tbls = d.get('identifiers', []); \
print(f'  {len(tbls)} table(s) in namespace \"$(NAMESPACE)\":\n'); \
[print('  •', t.get('name')) for t in tbls]"

# Trino SQL equivalent: DESCRIBE <table>  (schema + partition spec + sort order)
iceberg-table-meta: ## Full Iceberg table metadata via REST  NAMESPACE=<ns> TABLE=<name>  (≡ Trino: DESCRIBE)
	@[[ -n "$(TABLE)" ]] || { \
	  echo "❌  TABLE is required."; \
	  echo "    Usage: make iceberg-table-meta NAMESPACE=<ns> TABLE=<table>"; \
	  exit 1; }
	@echo "📐  GET /v1/namespaces/$(NAMESPACE)/tables/$(TABLE)  → localhost:$(_ICEBERG_REST_PORT)"
	@echo ""
	@curl -sf http://localhost:$(_ICEBERG_REST_PORT)/v1/namespaces/$(NAMESPACE)/tables/$(TABLE) \
	  | python3 -c "\
import sys, json; \
d = json.load(sys.stdin); \
meta = d.get('metadata', {}); \
schema = next((s for s in meta.get('schemas', []) if s.get('schema-id') == meta.get('current-schema-id')), {}); \
fields = schema.get('fields', []); \
print(f'  Format version : {meta.get(\"format-version\", \"?\")}'); \
print(f'  Table UUID     : {meta.get(\"table-uuid\", \"?\")}'); \
print(f'  Location       : {meta.get(\"location\", \"?\")}'); \
print(f'  Current schema : {meta.get(\"current-schema-id\", \"?\")} ({len(fields)} column(s))\n'); \
print(f'  {\"Column\":<30}  {\"Type\":<20}  Required'); \
print(f'  {\"-\"*30}  {\"-\"*20}  --------'); \
[print(f'  {f[\"name\"]:<30}  {f[\"type\"]:<20}  {\"yes\" if f.get(\"required\") else \"no\"}') for f in fields]"

# Trino SQL equivalent:
#   SELECT * FROM iceberg."\$snapshots" WHERE table_name='<table>'
#   (system table, available in Trino with Iceberg connector)
iceberg-snapshots: ## List snapshot history for an Iceberg table  NAMESPACE=<ns> TABLE=<name>
	@[[ -n "$(TABLE)" ]] || { \
	  echo "❌  TABLE is required."; \
	  echo "    Usage: make iceberg-snapshots NAMESPACE=<ns> TABLE=<table>"; \
	  exit 1; }
	@echo "📸  Snapshot history for $(NAMESPACE).$(TABLE):"
	@echo ""
	@curl -sf http://localhost:$(_ICEBERG_REST_PORT)/v1/namespaces/$(NAMESPACE)/tables/$(TABLE) \
	  | python3 -c "\
import sys, json, datetime; \
d = json.load(sys.stdin); \
snaps = d.get('metadata', {}).get('snapshots', []); \
current = d.get('metadata', {}).get('current-snapshot-id'); \
print(f'  {len(snaps)} snapshot(s)  |  current: {current}\n'); \
print(f'  {\"Snapshot ID\":<22}  {\"Timestamp\":<25}  {\"Operation\":<12}  {\"Added files\"}'); \
print(f'  {\"-\"*22}  {\"-\"*25}  {\"-\"*12}  -----------'); \
[print(f'  {str(s.get(\"snapshot-id\",\"?\")):<22}  {datetime.datetime.fromtimestamp(s.get(\"timestamp-ms\",0)/1000).isoformat():<25}  {s.get(\"summary\",{}).get(\"operation\",\"?\"):<12}  {s.get(\"summary\",{}).get(\"added-data-files\",\"?\")}{\" ◀ current\" if s.get(\"snapshot-id\") == current else \"\"}') \
  for s in snaps]"