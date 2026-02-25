# ============================================================
# Usage:
#   make up                   → start via Docker Compose (default)
#   make up USE_KIND=true     → provision kind cluster, then deploy
#   make down                 → stop (compose or kind, auto-detected)
#   make up ENV=prod          → compose prod overrides
# ============================================================

ENV          ?= dev
USE_KIND     ?= false
CLUSTER_NAME ?= local-cluster
KIND_CONFIG  ?= ../cluster/kind-config.yaml


# ── Compose setup ───────────────────────────────────────────
COMPOSE_BASE  = docker-compose.yml
COMPOSE_ENV   = docker-compose.$(if $(filter prod,$(ENV)),prod,$(if $(filter ci,$(ENV)),ci,override)).yml
DC            = docker compose -f ./compose/$(COMPOSE_BASE) -f ./compose/$(COMPOSE_ENV)

.PHONY: help up down build restart logs shell ps clean prune lint health smoke-test \
        kind-up kind-down kind-status compose-up compose-down

# ── Help ────────────────────────────────────────────────────
default: help
help: ## Show this help
	@echo ""
	@echo "  Usage: make <target> [USE_KIND=true] [ENV=dev|prod|ci]"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "  Examples:"
	@echo "    make up                  # Docker Compose (default)"
	@echo "    make up USE_KIND=true    # kind cluster + deploy"
	@echo "    make up ENV=prod         # Compose prod overrides"
	@echo ""

# ── .env bootstrap ──────────────────────────────────────────
.env:
	@cp .env.example .env
	@echo "⚠️  .env created from .env.example — update credentials before running"

# ── Entry points (branch on USE_KIND) ───────────────────────
ifeq ($(USE_KIND),true)

up: kind-up ## Start stack — kind cluster path (USE_KIND=true)

down: kind-down ## Tear down kind cluster

else

up: .env compose-up ## Start stack — Docker Compose path (default)

down: compose-down ## Stop Docker Compose stack

endif


# ── Docker Compose targets ───────────────────────────────────
compose-up: .env ## (internal) Start via Docker Compose
	@echo "🐳 Starting analytics stack via Docker Compose [ENV=$(ENV)]..."
	$(DC) up -d --remove-orphans
	@echo ""
	@echo "🚀 Stack is up:"
	@echo "   Trino UI          → http://localhost:$${TRINO_PORT:-8080}"
	@echo "   Iceberg REST      → http://localhost:$${ICEBERG_REST_PORT:-8181}"
	@echo "   MinIO Console     → http://localhost:$${MINIO_CONSOLE_PORT:-9001}"
	@echo "   Postgres          → localhost:5432 (dev only)"
	@echo ""

compose-down: ## (internal) Stop Docker Compose stack
	$(DC) down

build: ## Pull latest images
	$(DC) pull

restart: ## Restart all Compose services
	$(DC) restart

logs: ## Tail logs — make logs SERVICE=trino
	$(DC) logs -f $(SERVICE)

shell: ## Shell into a service — make shell SERVICE=trino
	$(DC) exec $(SERVICE) bash || $(DC) exec $(SERVICE) sh

ps: ## Show running containers and health status
	$(DC) ps

clean: ## Remove containers, networks, volumes — ⚠️  destroys data
	$(DC) down -v --remove-orphans

prune: ## Remove ALL unused Docker resources — ⚠️  dangerous
	docker system prune -af --volumes

lint: ## Validate compose config syntax
	$(DC) config --quiet && echo "✅ Compose config is valid"

# ── Kind cluster targets ─────────────────────────────────────
kind-up: ## (internal) Provision kind cluster and deploy stack
	@bash scripts/kind-deploy.sh up $(CLUSTER_NAME) $(KIND_CONFIG)

kind-down: ## (internal) Delete kind cluster
	@bash scripts/kind-deploy.sh down $(CLUSTER_NAME)

kind-status: ## Show kind cluster and pod status
	@bash scripts/kind-deploy.sh status $(CLUSTER_NAME)

# ── Health & smoke ───────────────────────────────────────────
health: ## Check health of all running services
	@bash scripts/health-check.sh


