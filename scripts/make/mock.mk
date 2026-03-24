# ── Mock service additions ─────────────────────────────────
# Append these blocks to your existing makefile.
# ──────────────────────────────────────────────────────────

# In the .env file, add:
#   WIREMOCK_VERSION=3.10.0-1
#   WIREMOCK_PORT=8090

mock: .env ## Start WireMock mock server (profile: mock)
	@echo "🎭 Starting WireMock mock server..."
	docker compose $(ENV_FILE_FLAGS) \
		--profile mock \
		$(foreach f,$(COMPOSE_FILE_LIST),-f $(f)) \
		up -d --remove-orphans
	@echo ""
	@echo "🚀 WireMock is up:"
	@echo "   Mock API      → http://localhost:$${WIREMOCK_PORT:-8090}"
	@echo "   Admin UI      → http://localhost:$${WIREMOCK_PORT:-8090}/__admin/"
	@echo "   Mappings API  → http://localhost:$${WIREMOCK_PORT:-8090}/__admin/mappings"
	@echo "   Stub guide    → config/wiremock/README.md"
	@echo ""

mock-reload: ## Hot-reload WireMock stubs from disk (no restart)
	@echo "🔄 Reloading WireMock stubs..."
	@curl -sf -X POST http://localhost:$${WIREMOCK_PORT:-8090}/__admin/mappings/reset \
	  && echo "✅ Stubs reloaded." \
	  || echo "❌ Could not reach WireMock — is it running? (make mock)"

mock-logs: ## Tail WireMock container logs
	docker compose $(ENV_FILE_FLAGS) \
		--profile mock \
		$(foreach f,$(COMPOSE_FILE_LIST),-f $(f)) \
		logs -f wiremock

mock-requests: ## Show recent requests received by WireMock (pretty-printed)
	@curl -sf http://localhost:$${WIREMOCK_PORT:-8090}/__admin/requests \
	  | python3 -m json.tool \
	  || echo "❌ Could not reach WireMock — is it running? (make mock)"

mock-reset-scenarios: ## Reset all WireMock scenario states to initial
	@curl -sf -X POST http://localhost:$${WIREMOCK_PORT:-8090}/__admin/scenarios/reset \
	  && echo "✅ Scenario states reset." \
	  || echo "❌ Could not reach WireMock."

mock-down: ## Stop WireMock container
	docker compose $(ENV_FILE_FLAGS) \
		--profile mock \
		$(foreach f,$(COMPOSE_FILE_LIST),-f $(f)) \
		down