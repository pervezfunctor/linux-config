# Proxmox Maintenance Helpers

Automation scripts under `py/` manage Proxmox hosts, orchestrate rolling maintenance, and keep manifests tidy. The tools share a common async core (`proxmox_maintenance.py`) plus interactive wizards for editing host inventories.

## Requirements & Setup
- Install [pixi](https://pixi.sh/) (recommended installer for mixing Conda + PyPI/uv tooling).
- Bootstrap the workspace once:
  ```bash
  cd py
  pixi install
  ```
- Open a shell with every dependency (including Conda packages) resolved:
  ```bash
  pixi shell           # or pixi shell -e runtime for the slim env
  ```
- Or run one-offs without activating the shell:
  ```bash
  pixi run lint        # wrappers are defined in pyproject.toml
  pixi run proxmox-batch -- --help
  ```
- `uv` still owns Python dependency resolution/locking. Continue to run `uv sync --extra dev` (or `uv lock`) when editing `pyproject.toml`, then re-run `pixi install` so `pixi.lock` picks up the changes.
- Helpful Make-style shortcuts live in `Maskfile.md`; use `mask <task>` (requires [`mask`](https://github.com/jakedeichert/mask)). Running `mask` from inside `pixi shell` keeps everything consistent.

## Project Layout
| File | Purpose |
| --- | --- |
| `proxmox_maintenance.py` | Core async workflow for a single host. Handles API auth, SSH sessions, guest upgrades, and logging. |
| `proxmox_batch.py` | Loads `proxmox-hosts.toml`, expands defaults, runs multiple hosts concurrently, and enforces credential checks. |
| `proxmox_config_wizard.py` | Questionary-based editor to add hosts, tweak defaults, and validate manifests before saving. |
| `proxmox_inventory_builder.py` | Discovers VMs/LXCs on a host and writes `guest_inventory` metadata entries. |
| `remote_maintenance.py` | Shared SSH helpers (`SSHSession`, guest upgrade orchestration, package manager detection). |
| `Maskfile.md` | `pixi run …` helper tasks (uv-powered) for linting, tests, and CLI shortcuts. |
| `tests/` | Pytest coverage for batch execution, maintenance workflow, and the wizard helpers. |

## Common Commands
```bash
mask lint          # pixi run lint (Ruff)
mask format        # pixi run fmt
mask typecheck     # pixi run typecheck (Pyright)
mask test          # pixi run test (pytest)
mask proxmox:run   # pixi run proxmox-maintenance -- …
mask proxmox:batch # pixi run proxmox-batch -- …
mask proxmox:config    # pixi run proxmox-wizard -- …
mask proxmox:inventory # pixi run proxmox-inventory -- …
```
(Each Mask task delegates to the pixi task graph, which runs `uv run …` under the hood.)

### Unified CLI (`proxmoxctl`)

All operational scripts now hang off a single Typer-powered CLI. Use `uv run proxmoxctl -- --help` to inspect the full tree. Key subcommands:

- `proxmoxctl maintenance run`: single-host lifecycle orchestration (replaces `proxmox_maintenance.py`).
- `proxmoxctl batch run`: fleet runner that loads `proxmox-hosts.toml`, filters hosts, and fans out via SSH.
- `proxmoxctl wizard run`: interactive manifest editor using Questionary.
- `proxmoxctl inventory configure`: guided guest discovery + credential capture for a manifest entry.

Legacy scripts remain runnable for now but emit a "use proxmoxctl" notice on start; prefer the unified CLI for new automation.

## Manifest (`py/proxmox-hosts.toml`)
`proxmox_batch.py` and the wizards share a single manifest schema so defaults and hosts stay versioned with the codebase. Example:

> Host-specific overrides for `identity_file`, `ssh.extra_args`, `guest.user`, and `guest.identity_file` were removed—set those in `[defaults]` so every host inherits the same credentials.

```toml
[defaults]
user = "root"
guest.user = "root"
identity_file = "~/.ssh/proxmox"
guest.identity_file = "~/.ssh/guest"
ssh.extra_args = ["-J", "bastion"]
guest.ssh.extra_args = ["-o", "StrictHostKeyChecking=no"]
max_parallel = 2
dry_run = false

[[hosts]]
name = "prod-a"
host = "proxmox-a.example.com"
api.node = "pve-a"
api.token_env = "PROXMOX_A_TOKEN"
api.secret_env = "PROXMOX_A_SECRET"

[[hosts]]
name = "prod-b"
host = "proxmox-b.example.com"
api.token_env = "PROXMOX_B_TOKEN"
api.secret_env = "PROXMOX_B_SECRET"
dry_run = true
```

Per host you must export the `api.token_env` + `api.secret_env` variables before running batch jobs (for CI use secrets/direnv). Optional keys such as `guest_inventory` are preserved by the wizards even if they are not explicitly documented here.

## CLI Reference
- `proxmoxctl maintenance run`: Lifecycle orchestrator for a single node—backs up VMs, drains guests, applies OS upgrades, and reboots while honoring manifest defaults and dry-run semantics.
- `proxmoxctl batch run`: Concurrency-aware launcher that reads `proxmox-hosts.toml`, verifies required secrets, and summarizes host results with CI-friendly exit codes.
- `proxmoxctl wizard run`: Questionary-driven editor for manifests, enabling host add/clone/delete workflows plus validation before persisting without clobbering unknown keys.
- `proxmoxctl inventory configure`: Guided guest discovery assistant that pulls VM/LXC metadata via the API, validates SSH/guest-agent access, and writes structured `guest_inventory` entries.
- Legacy module entrypoints (`proxmox_* .py`) still work via `uv run`, but favor `proxmoxctl` for a consistent surface and better help output.

## Remote Maintenance Helpers
`remote_maintenance.py` exposes:
- `SSHSession`: central dry-run aware SSH executor (sets StrictHostKeyChecking=no, configurable timeouts/identities).
- `attempt_guest_upgrade` / `upgrade_guest_operating_system`: detect guest OS via `/etc/os-release`, choose package manager commands, retry with alternate users if needed.
- Utility types (`GuestSSHOptions`, `CommandResult`) and error classes reused by maintenance scripts.

## Developing & Testing
1. Run `mask lint` / `mask format` before committing (Ruff reads settings from `pyproject.toml`).
2. Execute `mask typecheck` for Pyright's strict type checking.
3. Execute `mask test` to keep the Pytest suite green; async helpers rely on `pytest-asyncio`.
4. When dependencies change, run `uv lock` so `uv.lock` stays in sync with `pyproject.toml`.

For small experiments you can run any script directly with `uv run <script> -- --help` to inspect arguments without touching the system Python installation.
