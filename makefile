.PHONY: up down help

up: install-kind-deps up-kind-cluster
default: up

.PHONY: install-kind-deps
install-kind-deps: 
	@command -v kubectl >/dev/null 2>&1 || { echo >&2 "kubectl not found. Installing..."; curl -LO "https://storage.googleapis.com/kubernetes-release/release/`curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt`/bin/linux/amd64/kubectl"; chmod +x kubectl; sudo mv kubectl /usr/local/bin/; }
	@command -v kind >/dev/null 2>&1 || { echo >&2 "kind not found. Installing..."; curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.23.0/kind-linux-amd64; chmod +x ./kind; sudo mv ./kind /usr/local/bin/kind; }
	@command -v helm >/dev/null 2>&1 || { echo >&2 "helm not found. Installing..."; curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash; }
	@echo "All dependencies are installed."

.PHONY: up-kind-cluster
up-kind-cluster:
	@echo "Starting single-node Kubernetes cluster with kind..."
	@kind create cluster --name local-cluster --wait 60s --config cluster/kind-config.yaml >/dev/null 2>&1 || echo "Cluster may already exist."

down: down-kind-cluster

.PHONY: down-kind-cluster
down-kind-cluster:
	@echo "Stopping and deleting kind cluster..."
	@kind delete cluster --name local-cluster

help:
	@echo "Usage:"
	@echo "  make up          - Start kind cluster"
	@echo "  make down   			- Stop and delete the Kubernetes cluster"
	@echo "  make help        - Show help message"


