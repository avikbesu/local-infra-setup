---
name: Docker Compose host bind-mount path conventions
description: Where service configs and logs are stored on the host under compose/container/
type: project
---

All Docker Compose service bind-mount paths follow this convention under `compose/container/`:

- **Logs:** `compose/container/logs/<service_name>/`
- **Other configs (plugins, data, config files, etc.):** `compose/container/<config_name>/<service_name>/`

**Why:** Consistent host-side layout so every service's files are discoverable under `compose/container/`.
**How to apply:** When adding volume mounts for a new service, always use these paths. When debugging missing files or permission errors, check under `compose/container/`. Ensure directories exist with correct permissions before the container starts.
