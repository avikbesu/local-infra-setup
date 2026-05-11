# ── Observability stack (Prometheus · Grafana · cAdvisor) ────

obs-up: .env ## Start observability stack (Prometheus, Grafana, cAdvisor)
	@echo "📊 Starting observability stack..."
	docker compose $(ENV_FILE_FLAGS) \
		--profile observability \
		$(foreach f,$(COMPOSE_FILE_LIST),-f $(f)) \
		up -d --remove-orphans
	@echo ""
	@echo "🚀 Observability stack is up:"
	@echo "   Grafana     → http://localhost:$${GRAFANA_PORT:-3000}"
	@echo "   Prometheus  → http://localhost:$${PROMETHEUS_PORT:-9090}"
	@echo ""
	@echo "   Login: admin / (see .env.local for GRAFANA_ADMIN_PASSWORD)"
	@echo ""

obs-down: ## Stop observability stack
	docker compose $(ENV_FILE_FLAGS) \
		--profile observability \
		$(foreach f,$(COMPOSE_FILE_LIST),-f $(f)) \
		down

obs-logs: ## Tail observability logs  (SERVICE=prometheus|grafana|cadvisor)
	docker compose $(ENV_FILE_FLAGS) \
		--profile observability \
		$(foreach f,$(COMPOSE_FILE_LIST),-f $(f)) \
		logs -f $(SERVICE)
