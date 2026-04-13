---
paths:
  - "cluster/**"
  - "helm/**"
---

# Kubernetes Rules

## Single Registry

`cluster/helm-components.yaml` is the ONLY registry for Kubernetes components. All deploy, remove, and port-forward logic reads from this file. Never run `helm install` manually.

## Adding a Component

1. Register it in `cluster/helm-components.yaml`
2. Set resource limits in `helm/<component>/values.yaml` — never leave limits unset
3. Use `condition: service_healthy` in any `depends_on` entries inside the YAML registry
4. Test with `make kube-deploy-one COMPONENT=<name>` before running `make kube-up`

## Security Constraints

- Never bind `cluster-admin` to a workload service account
- Never use `network_mode: host` — use named networks
- Never put real secrets in Helm values files — reference `.env.local` vars only

## Useful Make Targets

- `make kube-up` — bring up all registered components
- `make kube-down` — tear down all components
- `make kube-deploy-one COMPONENT=<name>` — deploy a single component
- `make kube-remove-one COMPONENT=<name>` — remove a single component
