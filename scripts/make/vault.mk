# =============================================================================
##@ Vault — HashiCorp Vault secrets management
# =============================================================================

.PHONY: vault-up vault-down pipeline-vault

vault-up: .env ## Start Vault server and seed example secrets
	@echo "Starting Vault (dev mode)..."
	docker compose $(ENV_FILE_FLAGS) \
		--profile vault \
		$(foreach f,$(COMPOSE_FILE_LIST),-f $(f)) \
		up -d --remove-orphans
	@echo ""
	@echo "Vault is up:"
	@echo "   UI / API  → http://localhost:$${VAULT_PORT:-8200}"
	@echo "   Token     → \$$(grep VAULT_DEV_ROOT_TOKEN .env.local | cut -d= -f2)"
	@echo ""

vault-down: ## Stop Vault
	docker compose $(ENV_FILE_FLAGS) \
		--profile vault \
		$(foreach f,$(COMPOSE_FILE_LIST),-f $(f)) \
		down

pipeline-vault: .env airflow-dirs ## Start Airflow pipeline + Vault together
	@echo "Starting pipeline + Vault stack..."
	docker compose $(ENV_FILE_FLAGS) \
		--profile pipeline --profile vault \
		$(foreach f,$(COMPOSE_FILE_LIST),-f $(f)) \
		up -d --remove-orphans
	@echo ""
	@echo "Pipeline + Vault stack is up:"
	@echo "   Airflow UI → http://localhost:$${AIRFLOW_API_SERVER_PORT:-8081}"
	@echo "   Vault UI   → http://localhost:$${VAULT_PORT:-8200}"
	@echo ""
