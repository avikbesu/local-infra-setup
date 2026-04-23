# =============================================================================
# scripts/make/security.mk
# Security-related make targets: image scanning, hook setup.
# Included by root makefile via the scripts/make/*.mk glob.
# =============================================================================

.PHONY: setup scan scan-critical

setup: ## Activate git hooks (.githooks/pre-commit) for this repo clone
	@git config core.hooksPath .githooks
	@chmod +x .githooks/pre-commit
	@echo "✅ Git hooks activated — .githooks/pre-commit will run on every commit"
	@echo "   To deactivate: git config --unset core.hooksPath"

scan: ## Scan all pinned images for CVEs using Trivy (requires: trivy)
	@command -v trivy >/dev/null 2>&1 \
	  || { echo "❌ trivy not found. Install: https://aquasecurity.github.io/trivy/latest/getting-started/installation/"; exit 1; }
	@echo "🔍 Scanning images for CVEs (HIGH + CRITICAL)..."
	@echo ""
	@images=$$( \
	  grep -h 'image:' compose/docker-compose.*.yaml \
	    | grep -v '^\s*#' \
	    | sed 's/.*image:\s*//' \
	    | sed 's/\$${[^}]*}/SKIP/g' \
	    | grep -v 'SKIP\|fluentd-local\|iceberg-rest-local' \
	    | sort -u \
	); \
	for img in $$images; do \
	  echo "--- $$img ---"; \
	  trivy image --severity HIGH,CRITICAL --quiet "$$img" || true; \
	  echo ""; \
	done
	@echo "✅ Scan complete."

scan-critical: ## Scan images and exit non-zero if any CRITICAL CVEs found (CI use)
	@command -v trivy >/dev/null 2>&1 \
	  || { echo "❌ trivy not found"; exit 1; }
	@echo "🔍 Scanning for CRITICAL CVEs (CI gate)..."
	@images=$$( \
	  grep -h 'image:' compose/docker-compose.*.yaml \
	    | grep -v '^\s*#' \
	    | sed 's/.*image:\s*//' \
	    | sed 's/\$${[^}]*}/SKIP/g' \
	    | grep -v 'SKIP\|fluentd-local\|iceberg-rest-local' \
	    | sort -u \
	); \
	failed=0; \
	for img in $$images; do \
	  trivy image --severity CRITICAL --exit-code 1 --quiet "$$img" || failed=1; \
	done; \
	exit $$failed
