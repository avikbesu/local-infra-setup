## Local Claude Setup

Watch [tutorial](https://www.youtube.com/watch?v=AKKx1PoNtnM) if required.

```bash
# Install Ollama
curl -fsSL https://ollama.com/install.sh | sh

# Check Ollama
ollama --version
ollama ls

# Ollama pull model
# ollama pull gpt-oss:20b # best option on feb 2026 - not working in my wsl
ollama pull glm-4.7-flash # yet to check

# Ollama check model
ollama ls

# Change Ollama context length (very imp step)
export OLLAMA_CONTEXT_LENGTH=32000

# Install Claude
curl -fsSL https://claude.ai/install.sh | bash

# Run Claude with Ollama
export OLLAMA_CONTEXT_LENGTH=32000
# ollama launch claude --model gpt-oss:20b 
ollama launch claude --model glm-4.7-flash
```


