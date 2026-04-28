# =============================================================================
##@ Docker Compose — Service management
#
# Variables (overridable on the command line):
#   PROFILE   — comma-separated list of profiles to activate  (default: *)
#   SERVICE   — target service name for logs/shell targets
#
# Examples:
#   make up
#   make up PROFILE=pipeline
#   make logs SERVICE=trino
#   make shell SERVICE=postgres
# =============================================================================

# ── Read ICEBERG_REST_VERSION from .env (no -include, avoids .env remake loop) ─
ICEBERG_REST_VERSION := $(strip $(shell grep -s '^ICEBERG_REST_VERSION=' .env | cut -d= -f2))
ICEBERG_REST_VERSION := $(if $(ICEBERG_REST_VERSION),$(ICEBERG_REST_VERSION),0.10.0)

# ── Env files ────────────────────────────────────────────────────────────────
# .env holds non-secret defaults; .env.local holds secrets and local overrides.
# .env.local values take precedence (it is listed second).
ENV_FILE_FLAGS := --env-file .env $(if $(wildcard .env.local),--env-file .env.local)

# ── Compose setup ────────────────────────────────────────────────────────────
COMPOSE_GLOB      := $(wildcard ./compose/docker-compose*.yaml)
COMPOSE_FILE_LIST := $(COMPOSE_GLOB)

PROFILES      := $(strip $(shell echo "$(PROFILE)" | tr ',' ' '))
PROFILE_FLAGS := $(strip $(foreach p,$(PROFILES),$(if $(p),--profile "$(p)")))

# Master compose command — env files + profiles + compose files
DC := docker compose $(ENV_FILE_FLAGS) $(PROFILE_FLAGS) \
      $(foreach f,$(COMPOSE_FILE_LIST),-f $(f))

.PHONY: compose-up compose-down build restart logs shell ps clean prune lint \
        sync dagcheck airflow-dirs build-query query pipeline

# =============================================================================
# Core lifecycle
# =============================================================================

compose-up: .env ## (internal) Start via Docker Compose
	@echo "🐳 Starting your application(s) via Docker Compose [PROFILE=$(PROFILE)]..."
	$(DC) up -d --remove-orphans
	@echo ""
	@echo "🚀 Stack is up"

compose-down: ## (internal) Stop Docker Compose stack
	$(DC) down

build: ## Pull latest images
	$(DC) pull

restart: .env ## Restart all Compose services
	$(DC) down
	$(DC) up -d --remove-orphans
	@echo ""
	@echo "🚀 Stack is restarted"

# =============================================================================
# Service operations
# =============================================================================

logs: ## Tail logs — make logs SERVICE=trino
	$(DC) logs -f $(SERVICE)

shell: ## Shell into a service — make shell SERVICE=trino
	$(DC) exec $(SERVICE) bash || $(DC) exec $(SERVICE) sh

ps: ## Show running containers and health status
	$(DC) ps

# =============================================================================
# Maintenance
# =============================================================================

clean: ## Remove containers, networks, volumes — ⚠️  destroys data
	$(DC) down -v --remove-orphans

prune: ## Remove ALL unused Docker resources — ⚠️  dangerous
	docker system prune -af --volumes

lint: ## Validate compose config syntax
	$(DC) config --quiet && echo "✅ Compose config is valid"

sync: ## Perform git submodule sync
	git submodule update --remote

# =============================================================================
# Application-specific targets
# =============================================================================

dagcheck: ## Airflow DAGs check
	@echo "Checking DAGs for errors..."
	$(DC) exec -w /opt/airflow airflow-scheduler python3 scripts/infra/check_dags.py

airflow-dirs: ## Create Airflow log/plugin dirs with correct permissions (UID 50000 / GID 0)
	@mkdir -p compose/container/logs/airflow compose/container/plugins/airflow
	@chmod 777 compose/container/logs/airflow compose/container/plugins/airflow

build-query: ## Build custom iceberg-rest image (skips if already present)
	@if docker image inspect iceberg-rest-local:$(ICEBERG_REST_VERSION) \
	        >/dev/null 2>&1; then \
	  echo "✅ iceberg-rest-local:$(ICEBERG_REST_VERSION) already exists — skipping build."; \
	else \
	  echo "🔨 Building iceberg-rest-local:$(ICEBERG_REST_VERSION)..."; \
	  docker build \
	    --build-arg ICEBERG_REST_VERSION=$(ICEBERG_REST_VERSION) \
	    --tag iceberg-rest-local:$(ICEBERG_REST_VERSION) \
	    compose/iceberg-rest/; \
	  echo "✅ iceberg-rest-local:$(ICEBERG_REST_VERSION) built"; \
	fi

query: .env build-query ## Start query engine stack (Trino + Iceberg REST + Postgres + MinIO)
	@echo "🔍 Starting query engine stack..."
	docker compose $(ENV_FILE_FLAGS) \
		--profile query --profile db --profile storage \
		$(foreach f,$(COMPOSE_FILE_LIST),-f $(f)) \
		up -d --remove-orphans
	@echo ""
	@echo "🚀 Query stack is up:"
	@echo "   Trino UI      → http://localhost:$${TRINO_PORT:-8080}"
	@echo "   Iceberg REST  → http://localhost:$${ICEBERG_REST_PORT:-8181}"
	@echo "   MinIO Console → http://localhost:$${MINIO_CONSOLE_PORT:-9001}"
	@echo "   Postgres      → localhost:$${POSTGRES_PORT:-5432} (dev only)"
	@echo ""

pipeline: .env airflow-dirs ## Start pipeline stack (Airflow + Postgres)
	@echo "🔍 Starting pipeline stack..."
	docker compose $(ENV_FILE_FLAGS) \
		--profile pipeline \
		$(foreach f,$(COMPOSE_FILE_LIST),-f $(f)) \
		up -d --remove-orphans
	@echo ""
	@echo "🚀 Pipeline stack is up:"
	@echo "   Airflow UI    → http://localhost:$${AIRFLOW_API_SERVER_PORT:-8081}"
	@echo "   Postgres      → localhost:$${POSTGRES_PORT:-5432} (dev only)"
	@echo ""
