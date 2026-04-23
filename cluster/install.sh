#!/usr/bin/env bash
# Install kind — Kubernetes in Docker
# https://kind.sigs.k8s.io/docs/user/using-wsl2/
# https://kind.sigs.k8s.io/docs/user/quick-start/
set -euo pipefail

KIND_VERSION="v0.27.0"
ARCH="$(uname -m)"

case "$ARCH" in
  x86_64)  curl -Lo ~/kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64" ;;
  aarch64) curl -Lo ~/kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-arm64" ;;
  *)       echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

chmod +x ~/kind
sudo mv ~/kind /usr/local/bin/kind
echo "kind ${KIND_VERSION} installed to /usr/local/bin/kind"