#!/usr/bin/env bash
# =============================================================================
# scripts/kube-status.sh
# Shows cluster health, helm release status for all enabled components,
# and running pod counts per namespace.
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/lib/kube-common.sh"

require_yq
require_kubectl
require_helm

CLUSTER_NAME="${KIND_CLUSTER_NAME:-local-cluster}"
CTX="kind-${CLUSTER_NAME}"

log_step "Cluster"
if kubectl cluster-info --context "$CTX" &>/dev/null; then
  kubectl cluster-info --context "$CTX" 2>/dev/null | grep "Kubernetes control plane"
  echo ""
  kubectl get nodes --context "$CTX" -o wide
else
  log_warn "Cluster '${CLUSTER_NAME}' is not running."
  exit 0
fi

echo ""
log_step "Helm Releases (enabled components)"
count=$(count_enabled)

for i in $(seq 0 $((count - 1))); do
  name=$(enabled_field "$i" name)
  namespace=$(enabled_field "$i" namespace)

  status=$(helm status "$name" -n "$namespace" -o json 2>/dev/null \
    | yq '.info.status' 2>/dev/null || echo "not-installed")

  case "$status" in
    deployed)      echo -e "  ${GREEN}●${RESET} $name (ns: $namespace) — ${GREEN}$status${RESET}" ;;
    not-installed) echo -e "  ${YELLOW}○${RESET} $name (ns: $namespace) — ${YELLOW}not installed${RESET}" ;;
    *)             echo -e "  ${RED}●${RESET} $name (ns: $namespace) — ${RED}$status${RESET}" ;;
  esac
done

echo ""
log_step "Pods (all namespaces)"
kubectl get pods -A --context "$CTX" \
  --sort-by=.metadata.namespace \
  -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[0].ready'

echo ""
log_step "Port-Forward Processes"
pgrep -a "kubectl port-forward" 2>/dev/null \
  | awk '{$1=""; print "  " $0}' \
  || echo "  (none running)"