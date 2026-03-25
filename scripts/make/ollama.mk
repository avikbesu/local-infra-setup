# Ollama commands for launching Claude Code

OLLAMA_MODEL ?= glm-5:cloud		 # minimax-m2.5:cloud

.PHONY: ollama ollama-stop
ollama: ## Launch Claude Code with Ollama (model from OLLAMA_MODEL, default: minimax-m2.5:cloud)
	@ollama launch claude --model $(OLLAMA_MODEL)

ollama-stop: ## Stop Ollama server
	@ollama stop $(OLLAMA_MODEL)