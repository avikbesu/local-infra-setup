# Ollama commands for launching Claude Code

OLLAMA_MODEL ?= qwen2.5-coder:7b		 # minimax-m2.5:cloud		glm-5:cloud  gemma4:e2b-it-q4_K_M

.PHONY: ollama ollama-stop
ollama: ## Launch Claude Code with Ollama (model from OLLAMA_MODEL, default: qwen2.5-coder:7b)
	@ollama launch claude --model $(OLLAMA_MODEL)

ollama-install: ## Install latest ollama
	@curl -fsSL https://ollama.com/install.sh | sh

ollama-check: ## Validate whether ollama installed
	@ollama -version 

ollama-list: ## List ollama model downloaded
	@ollama ls

ollama-stop: ## Stop Ollama server
	@ollama stop $(OLLAMA_MODEL)