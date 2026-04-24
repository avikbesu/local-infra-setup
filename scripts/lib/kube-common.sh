#!/usr/bin/env bash
# =============================================================================
# scripts/lib/kube-common.sh
# Kubernetes-specific utilities. Sources lib/common.sh for base logging,
# error handling, and tool validation.
#
# Source with:  source "$(dirname "${BASH_SOURCE[0]}")/lib/kube-common.sh"
# =============================================================================

# ── Base library ─────────────────────────────────────────────────────────────
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# ── Config file ───────────────────────────────────────────────────────────────
HELM_COMPONENTS_CONFIG="${HELM_COMPONENTS_CONFIG:-${REPO_ROOT}/cluster/helm-components.yaml}"

# ── Tool guards ───────────────────────────────────────────────────────────────
require_yq() {
  require_tool yq "https://github.com/mikefarah/yq/releases  or  brew install yq"
  local ver
  ver=$(yq --version 2>&1)
  [[ "$ver" == *"mikefarah"* || "$ver" == *"(https://github.com/mikefarah/yq)"* || "$ver" =~ v4\. ]] \
    || die "yq v4 (mikefarah) is required. Found: $ver"
}

require_helm()    { require_tool helm    "https://helm.sh/docs/intro/install/"; }
require_kubectl() { require_tool kubectl "https://kubernetes.io/docs/tasks/tools/"; }
require_kind()    { require_tool kind    "https://kind.sigs.k8s.io/docs/user/quick-start/#installation"; }

# ── Kind context ──────────────────────────────────────────────────────────────
# Returns the kubectl context name for the local kind cluster.
get_kind_context() {
  echo "kind-${KIND_CLUSTER_NAME:-local-cluster}"
}

# ── YQ helpers ────────────────────────────────────────────────────────────────
# Count enabled components.
count_enabled() {
  yq '[.components[] | select(.enabled == true)] | length' "$HELM_COMPONENTS_CONFIG"
}

# Field value for the i-th enabled component (0-based).
# Usage: enabled_field <index> <field>
enabled_field() {
  local idx="$1" field="$2"
  yq "[.components[] | select(.enabled == true)][$idx].${field}" "$HELM_COMPONENTS_CONFIG"
}

# All values of a field across enabled components (newline-separated).
# Usage: all_enabled_field <field>
all_enabled_field() {
  yq '.components[] | select(.enabled == true) | .'"$1" "$HELM_COMPONENTS_CONFIG"
}

# depends_on list for the i-th enabled component.
# Usage: enabled_deps <index>  → space-separated names
enabled_deps() {
  local idx="$1"
  yq "[.components[] | select(.enabled == true)][$idx].depends_on[]" \
    "$HELM_COMPONENTS_CONFIG" 2>/dev/null | tr '\n' ' '
}

# pre_manifests list for the i-th enabled component.
# Usage: enabled_manifests <index>  → newline-separated paths
enabled_manifests() {
  local idx="$1"
  yq "[.components[] | select(.enabled == true)][$idx].pre_manifests[]" \
    "$HELM_COMPONENTS_CONFIG" 2>/dev/null
}

# port_forward entries for a named component.
# Usage: component_port_forwards <name>  → lines of "service:local:remote"
component_port_forwards() {
  local name="$1"
  yq ".components[] | select(.name == \"$name\" and .enabled == true) \
      | .port_forward[] | .service + \":\" + (.local_port | tostring) + \":\" + (.remote_port | tostring)" \
    "$HELM_COMPONENTS_CONFIG" 2>/dev/null
}

# ── Pod listing ───────────────────────────────────────────────────────────────
# Outputs one line per pod with space-separated fields (no headers).
# Filters by the standard Helm instance label on the component's namespace.
#
# Usage: list_component_pods <component-name> <namespace> [custom-columns-spec]
# Default columns: NAME PHASE READY
list_component_pods() {
  local name="$1" ns="$2"
  local ctx cols
  ctx=$(get_kind_context)
  cols="${3:-NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready}"
  kubectl get pods -n "$ns" \
    -l "app.kubernetes.io/instance=${name}" \
    --context "$ctx" \
    --no-headers \
    --output="custom-columns=${cols}" \
    2>/dev/null || true
}

# ── Pre-flight file-reference check ──────────────────────────────────────────
# Asserts that the values_file and every pre_manifest for ALL enabled components
# exist on disk before any helm operation starts. Call once at the top of
# kube-deploy.sh so failures are reported together, not mid-deployment.
validate_enabled_files() {
  local count errs=0
  count=$(count_enabled)
  for i in $(seq 0 $(( count - 1 ))); do
    local name values_rel values_abs manifest_count m mrel mabs
    name=$(enabled_field "$i" name)
    values_rel=$(enabled_field "$i" values_file)
    values_abs="${REPO_ROOT}/${values_rel}"

    if [[ ! -f "$values_abs" ]]; then
      log_error "Component '$name': values_file not found: $values_rel"
      errs=$(( errs + 1 ))
    fi

    manifest_count=$(yq "[.components[] | select(.enabled == true)][$i].pre_manifests | length" \
      "$HELM_COMPONENTS_CONFIG" 2>/dev/null || echo 0)
    for m in $(seq 0 $(( manifest_count - 1 ))); do
      mrel=$(yq "[.components[] | select(.enabled == true)][$i].pre_manifests[$m]" \
        "$HELM_COMPONENTS_CONFIG" 2>/dev/null)
      [[ "$mrel" == "null" || -z "$mrel" ]] && continue
      mabs="${REPO_ROOT}/${mrel}"
      if [[ ! -f "$mabs" ]]; then
        log_error "Component '$name': pre_manifest not found: $mrel"
        errs=$(( errs + 1 ))
      fi
    done
  done
  [[ $errs -eq 0 ]] || die "Pre-flight check failed — $errs missing file(s). Aborting before any deploy."
}

# ── Topological sort ──────────────────────────────────────────────────────────
# Writes an ordered list of component *indices* (into the enabled array) to stdout.
# Uses Kahn's algorithm; exits non-zero on cycle detection.
topo_sort_indices() {
  require_yq
  local count
  count=$(count_enabled)
  local -a names=() deps=()
  local i

  for i in $(seq 0 $((count - 1))); do
    names[$i]=$(enabled_field "$i" name)
    deps[$i]=$(enabled_deps "$i")
  done

  local -a in_degree=()
  for i in $(seq 0 $((count - 1))); do
    local d=0
    for dep in ${deps[$i]}; do
      for j in $(seq 0 $((count - 1))); do
        [[ "${names[$j]}" == "$dep" ]] && { d=$(( d + 1 )); break; }
      done
    done
    in_degree[$i]=$d
  done

  local -a queue=() result=()
  for i in $(seq 0 $((count - 1))); do
    [[ "${in_degree[$i]}" -eq 0 ]] && queue+=("$i")
  done

  while [[ ${#queue[@]} -gt 0 ]]; do
    local cur="${queue[0]}"
    queue=("${queue[@]:1}")
    result+=("$cur")
    for i in $(seq 0 $((count - 1))); do
      for dep in ${deps[$i]}; do
        if [[ "$dep" == "${names[$cur]}" ]]; then
          in_degree[$i]=$(( in_degree[$i] - 1 ))
          [[ "${in_degree[$i]}" -eq 0 ]] && queue+=("$i")
        fi
      done
    done
  done

  if [[ ${#result[@]} -ne $count ]]; then
    die "Circular dependency detected in helm-components.yaml"
  fi

  printf '%s\n' "${result[@]}"
}
