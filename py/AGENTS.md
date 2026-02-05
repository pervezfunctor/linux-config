# PY/AGENT.md

Guidance for AI agents working inside the `py/` tooling workspace that powers the Proxmox maintenance helpers.

## Directory Snapshot

```
py/
├── pyproject.toml          # project + dev dependencies (Python >=3.12)
├── uv.lock                 # resolved dependency graph (managed via `uv lock`)
├── proxmox_maintenance.py  # core async workflow for a single Proxmox host
├── proxmox_batch.py        # manifest loader + orchestrator for multiple hosts
├── proxmox_config_wizard.py# Questionary-based manifest editor
├── proxmox_inventory_builder.py # interactive guest discovery + metadata capture
├── remote_maintenance.py   # shared SSH/session utilities
├── proxmox-hosts.toml      # sample manifest consumed by the batch runner
├── Maskfile.md             # handy `uv run …` shortcuts (lint/test/proxmox tasks)
└── tests/                  # pytest suite (batch/config wizard/maintenance helpers)
```

## Tooling & Commands

- Python version: 3.12+. Use `pixi shell` (or `pixi run …`) to ensure the Conda + uv toolchain is active. Pixi installs Conda artifacts while uv resolves PyPI deps.
- Dependency management: `uv lock` (already committed) + `pyproject.toml`. After touching dependencies run `uv lock`, then `pixi install` to refresh `pixi.lock`.
- Linting: `pixi run lint` (`uv run --extra dev ruff check`, line length 110, `target-version = "py312"`).
- Formatting: `pixi run fmt` (`uv run --extra dev ruff format`).
- Typing: `pixi run typecheck` (`uv run --extra dev pyright`, strict mode). Always run before handing work back.
- Tests: `pixi run test` (`uv run --extra dev pytest`, Pytest + pytest-asyncio).
- Mask shortcuts mirror the above (`mask proxmox:…`). Keep Maskfile entries updated when adding scripts.

## Architectural Notes

- `proxmox_maintenance.py`: async entry point per host. Shells into Proxmox over SSH for both inventory (via `qm`/`pct` CLI) and lifecycle actions. Watch for structured logging via `logging`. Guest upgrades use helpers from `remote_maintenance.py`.
- `proxmox_batch.py`: parses `proxmox-hosts.toml`, expands defaults, launches multiple maintenance runs, and handles credential env vars. Manifest schema must stay backward compatible.
- `proxmox_config_wizard.py`: Questionary wizard that manipulates manifests while preserving unknown keys and validating via `proxmox_batch.load_manifest`.
- `proxmox_inventory_builder.py`: extends the wizard flow to query live hosts via SSH, capture per-guest metadata (managed/noted), and writes `guest_inventory` blocks back into manifests.
- `remote_maintenance.py`: home for SSH/session abstractions, command execution, guest upgrade orchestration.

## Coding Standards

- Prefer `asyncio` + async HTTP/SSH patterns already in place.
- Model configs/state with `pydantic.BaseModel` so manifests and runtime data get validated automatically.
- Validate external data using Pydantic (`BaseModel`) or explicit type guards.
- Keep Questionary loops resilient to `None` (user abort) and surface friendly error messages.
- Expand user paths via `Path(...).expanduser()` before use; avoid bare `~` in runtime logic.
- Maintain manifest compatibility: call `proxmox_batch.load_manifest` or reuse helpers before saving.
- Log through `logging` (no print statements) and respect existing log format.

## Testing Expectations

1. **Unit tests**: add/extend files under `py/tests/` for any non-trivial change.
2. **Lint/type**: run Ruff + Pyright every time (per the user’s request).
3. **Runtime sanity**: when adding CLI entry points, at least ensure `python3 -m compileall` passes or run the script’s `--help`.

## Common Pitfalls & Tips

- Environment variables: manifests may reference environment variables for guest credentials (e.g., `password_env`). Never hardcode secrets directly into TOML.
- Questionary prompts should be localized (no stray newline formatting) and catch `WizardAbort`.
- When adding SSH features, reuse `SSHSession` or Paramiko wrappers; keep timeouts and key handling consistent with `remote_maintenance.py`.
- Updates to `pyproject.toml` require regenerating `uv.lock` (`uv lock`). Commit both files.
- Sample manifests live at `py/proxmox-hosts.toml`; keep them minimal but valid so docs/tests don’t break.

Following these conventions keeps the Proxmox tooling consistent with the rest of the repository and avoids surprises for future agents.
