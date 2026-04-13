---
paths:
  - "makefile"
  - "scripts/make/**"
---

# Makefile Rules

## Every Operation Needs a Target

Every new repeatable operation must have a `make` target. Users and CI interact exclusively through `make` — never via raw `docker compose`, `helm`, or `kubectl` directly.

## Required for Every New Target

```makefile
.PHONY: my-target
my-target: ## Brief description shown in make help
	@command-here
```

- Declare in `.PHONY`
- Add a `## Description` comment on the same line — `make help` parses this format
- Group the target under the appropriate sub-makefile in `scripts/make/*.mk`

## Organisation

Sub-makefiles are included by the root makefile glob. Adding a new `.mk` file in `scripts/make/` is enough — no manual registration needed.

## Never Expose docker compose Directly

All Docker Compose operations must go through `make` targets. This ensures consistent env var loading, profile handling, and `.env.local` injection.
