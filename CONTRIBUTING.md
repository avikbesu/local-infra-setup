# Contributing

## Prerequisites

Required tools: `docker`, `kubectl`, `kind`, `helm`, `yq`, `gh`, `python3`.

```bash
# Check what's installed (add --install to auto-install missing tools)
make check-deps
```

`gh` cannot be auto-installed on all systems. If `make check-deps --install` doesn't install it, use the manual command below (Ubuntu/Debian):

```bash
(type -p wget >/dev/null || (sudo apt update && sudo apt install wget -y)) \
    && sudo mkdir -p -m 755 /etc/apt/keyrings \
    && out=$(mktemp) && wget -nv -O$out https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    && cat $out | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
    && sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && sudo mkdir -p -m 755 /etc/apt/sources.list.d \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
       | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && sudo apt update && sudo apt install gh -y
```

Then authenticate:

```bash
gh auth login
```

## Local Setup

```bash
git clone --recurse-submodules git@github.com:avikbesu/local-infra-setup.git
cd local-infra-setup

# Activate git pre-commit hooks (blocks .env.local commits, validates compose, scans for secrets)
make setup

# Generate secrets into .env.local (auto-runs on first `make up`)
make secrets

# Start the full stack and verify health
make up
make health
```

The `make setup` step is required only once per clone. It activates `.githooks/pre-commit` which:
- Blocks accidental staging of `.env.local`
- Runs `make lint` when any compose file is changed
- Scans staged files for common hardcoded secret patterns

## Project Structure

```
compose/          # One yaml per service group, auto-included by makefile glob
scripts/make/     # Sub-makefiles included by root makefile (query, mock, ollama, proxy)
scripts/          # Shell scripts for cluster ops, secret gen, health checks
cluster/          # Kind config + helm-components.yaml (Kubernetes deployment registry)
helm/             # Helm values files per component
config/           # Per-service config files (Trino catalog, Postgres init, WireMock stubs)
dags/             # Git submodule (airflow3-by-example) — do not edit directly here
```

## Making Changes

### Adding a New Compose Service

1. Create or extend a file in `compose/docker-compose.<group>.yaml`
2. Assign it a profile — new files in `compose/` are **automatically included** by the makefile glob
3. Add health checks for stateful services using `condition: service_healthy` in all `depends_on` blocks
4. Expose only ports needed for local dev; use service names (not `localhost`) for inter-service communication
5. Add any new `make` targets to the relevant `scripts/make/*.mk` file, or create a new one and `include` it in the root `makefile`

### Adding a Kubernetes Component

Add an entry to `cluster/helm-components.yaml`:

```yaml
- name: my-service
  chart: repo/chart-name
  helm_repo: repo-alias
  helm_repo_url: https://charts.example.com
  namespace: my-ns
  values_file: helm/my-service/values.yaml
  wait_timeout: "5m"
  depends_on: []          # component names that must deploy first
  pre_manifests: []       # kubectl manifests applied before helm install
  port_forward: []        # {service, local_port, remote_port} entries
  enabled: true
```

Then add a `helm/my-service/values.yaml` with all resource limits set.

**`pre_manifests` vs Helm chart:** Use `pre_manifests` for resources the chart cannot create itself — PersistentVolumes, PersistentVolumeClaims, CRDs, or cross-namespace resources. They are applied with `kubectl apply` before `helm install` runs. Example: Airflow's `helm/airflow/dags_pv.yaml` and `dags_pvc.yaml` define the DAG volume that the chart mounts but doesn't own.

### Testing a Kubernetes Component Locally

```bash
# 1. Check all required tools are installed
make check-deps

# 2. Add Helm repos for all enabled components
make helm-repos

# 3. Validate the registry YAML and run helm template dry-run (no cluster needed)
make kube-validate-render

# 4. Start the kind cluster (idempotent — no-op if already running)
make kube-start

# 5. Create K8s Secrets from .env.local
make kube-secrets

# 6. Deploy your component only (dependency order is resolved automatically)
make kube-deploy-one COMPONENT=my-service

# 7. Watch pod readiness
kubectl get pods -n my-ns -w

# 8. Port-forward to test locally
make kube-port-forward

# 9. Tear down when done
make kube-remove-one COMPONENT=my-service
```

### Kubernetes Debugging Checklist

| Symptom | First command |
|---------|---------------|
| Pod stuck in `Pending` | `kubectl describe pod <pod> -n <ns>` → check Events section for resource/scheduling reason |
| Pod in `CrashLoopBackOff` | `kubectl logs <pod> -n <ns> --previous` to see the last crash output |
| Pod `OOMKilled` | Increase `resources.limits.memory` in `helm/<component>/values.yaml` and redeploy |
| `ImagePullBackOff` | Verify the image tag is pinned and the registry is reachable from the kind node |
| Helm install times out | Check if `depends_on` components are healthy first; increase `wait_timeout` if pods are slow to start |
| RBAC errors in pod logs | `kubectl auth can-i <verb> <resource> --as=system:serviceaccount:<ns>:<sa> -n <ns>` |
| Secret missing | Confirm `make kube-secrets` ran successfully; check with `kubectl get secret -n <ns>` |
| Port-forward not working | Check `make kube-port-forward-status`; stop and restart with `make kube-port-forward-stop && make kube-port-forward` |

### Resource Sizing for kind

kind runs on a single node. All component resource limits share the same host CPU and RAM. Recommended host minimums and per-component budgets:

| Component | CPU limit | Memory limit | Namespace |
|-----------|-----------|--------------|-----------|
| postgres | 500m | 512Mi | db |
| airflow scheduler | 1000m | 1Gi | af |
| airflow api-server | 500m | 768Mi | af |
| airflow dag-processor | 500m | 512Mi | af |
| airflow triggerer | 200m | 256Mi | af |
| wiremock | 200m | 256Mi | misc |
| nginx | 200m | 128Mi | misc |

**Total (enabled set):** ~3.1 vCPU / ~3.5 GiB  
**Recommended host:** 4 vCPU / 6 GiB free for the kind VM  

If pods are OOMKilled or evicted, check node pressure with:
```bash
kubectl describe node | grep -A 10 "Allocated resources"
```

### When to Use kind vs Docker Compose

| Scenario | Use |
|----------|-----|
| Day-to-day data engineering / DAG development | Docker Compose (`make up`) |
| Testing a new Helm chart or K8s manifest | kind (`make kube-deploy-one`) |
| Validating K8s RBAC, secrets, or probe behaviour | kind |
| Running the full query stack (Trino + Iceberg + MinIO) | Docker Compose (`make query`) |
| Reproducing a production-like K8s environment | kind |

### Adding or Rotating Secrets

Secrets are defined in `config/secrets.yaml` and generated into `.env.local`.

```bash
# Add a new secret key to config/secrets.yaml, then:
make secrets

# Rotate specific keys without touching others:
make rotate KEYS=MY_SECRET_KEY
```

Never add secret values to `.env`, `docker-compose*.yaml`, or Helm values files.

### Updating DAGs

The `dags/` directory is a git submodule pointing to `avikbesu/airflow3-by-example`.

```bash
# Pull latest DAGs
make sync

# Or pull and push changes from within the submodule
cd dags
git checkout main
git pull origin main
# ... make changes, commit, push
```

## Commit Convention

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
feat:     new service, profile, or capability
fix:      broken healthcheck, config error, dependency ordering
chore:    version bumps, gitignore, tooling
refactor: restructure without behaviour change
docs:     README, FAQ, CONTRIBUTING updates
```

Branch naming: `feat/<short-description>`, `fix/<issue-description>`, `chore/<task>`.

## Validation

Before opening a pull request:

```bash
# Validate all compose files parse correctly
make lint

# Bring up the relevant stack and confirm services reach healthy state
make up          # or make query / make pipeline
make health

# If touching Airflow DAGs
make dagcheck
```

## Antipatterns to Avoid

- No `latest` image tags — always pin to a specific version in both compose files and `helm/*/values.yaml`
- No bare `depends_on` — always use `condition: service_healthy` or `condition: service_completed_successfully`
- No secrets in committed files — `.env.local` is git-ignored for a reason
- No `network_mode: host` — use named networks and service-name hostnames
- No `cluster-admin` bindings for workload service accounts
