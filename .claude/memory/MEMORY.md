# Memory Index

- [Docker Compose host bind-mount path conventions](project_compose_paths.md) — logs at `compose/container/logs/<service_name>/`, other configs at `compose/container/<config_name>/<service_name>/`
- [Kubernetes secrets architecture](project_kube_secrets_arch.md) — K8s Secrets managed by `make kube-secrets` / `kube-secrets.sh`, never in Helm values files
- [Docker Compose stack analysis](project_compose_analysis.md) — profiles, image tag status, dependency chains, resource limits gaps
- [Helm / Kubernetes deployment architecture](project_helm_deployment.md) — component registry, port-forwards, nginx routes, known gaps
