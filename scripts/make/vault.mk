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
	@echo "   Token     → $$(grep VAULT_DEV_ROOT_TOKEN .env.local | cut -d= -f2)"
	@echo ""

vault-down: ## Stop Vault and remove .env.vault so Airflow stops using VaultBackend
	docker compose $(ENV_FILE_FLAGS) \
		--profile vault \
		$(foreach f,$(COMPOSE_FILE_LIST),-f $(f)) \
		down
	@rm -f .env.vault
	@echo "  🗑  .env.vault removed — Airflow will use DB secrets on next restart"

# Creates .env.vault which activates VaultBackend inside Airflow containers.
# The file is git-ignored and absent by default so `make pipeline` never touches Vault.
.env.vault:
	@{ \
	  echo 'AIRFLOW__SECRETS__BACKEND=airflow.providers.hashicorp.secrets.vault.VaultBackend'; \
	  echo 'AIRFLOW__SECRETS__BACKEND_KWARGS={"connections_path":"airflow/connections","variables_path":"airflow/variables","url":"http://vault:8200","auth_type":"token","kv_engine_version":2}'; \
	} > .env.vault
	@echo "  ✅ .env.vault created — VaultBackend will be active on next Airflow start"

pipeline-vault: .env .env.vault build-pipeline airflow-dirs ## Start Airflow pipeline + Vault together
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
