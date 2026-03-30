# =============================================================================
# ADD TO: makefile
# Location: under the ##@ Compose section, alongside existing * targets
#
# The PROXY_FLAGS variable follows the same lazy-expansion pattern (=) as
# other FLAGS vars in the makefile to avoid immediate evaluation of env files.
#
# Paste the variable definition near the other FLAGS definitions at the top,
# and paste the targets into the ##@ Compose section.
# =============================================================================


# --- Add inside ##@ Compose section ------------------------------------------

##@ Compose — Proxy

proxy-up: ## Start full stack + nginx reverse proxy (port ${NGINX_PORT:-80})
	docker compose $(ENV_FILE_FLAGS) \
		$(foreach f,$(COMPOSE_FILE_LIST),-f $(f)) \
	  --profile storage \
	  --profile db \
	  --profile logging \
	  --profile query \
	  --profile pipeline \
	  --profile proxy \
	  up -d --remove-orphans

proxy-down: ## Stop full stack + proxy
	docker compose $(ENV_FILE_FLAGS) \
		$(foreach f,$(COMPOSE_FILE_LIST),-f $(f)) \
	  --profile storage \
	  --profile db \
	  --profile logging \
	  --profile query \
	  --profile pipeline \
	  --profile proxy \
	  down

proxy-logs: ## Tail nginx logs
	docker compose $(ENV_FILE_FLAGS) \
		$(foreach f,$(COMPOSE_FILE_LIST),-f $(f)) \
	 --profile proxy \
	 logs -f nginx

proxy-reload: ## Hot-reload nginx config (no downtime)
	docker exec nginx nginx -s reload