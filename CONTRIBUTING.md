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

# Generate secrets into .env.local (auto-runs on first `make up`)
make secrets

# Start the full stack and verify health
make up
make health
```

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
