# Proxmox Maintenance Helpers

Automation scripts under `py/` manage Proxmox hosts, orchestrate rolling maintenance, and keep manifests tidy. The tools share a common async core (`proxmox_maintenance.py`) plus interactive wizards for editing host inventories.

## Requirements & Setup
- Python 3.12 or newer.
- [`uv`](https://github.com/astral-sh/uv) for reproducible runs (`pipx install uv`).
- Install dependencies (dev extras include Ruff, Pyright, and pytest):
  ```bash
  uv sync --extra dev
  ```
- Helpful Make-style shortcuts live in `Maskfile.md`; use `mask <task>` (requires [`mask`](https://github.com/jakedeichert/mask)).

## Project Layout
| File | Purpose |
| --- | --- |
| `proxmox_maintenance.py` | Core async workflow for a single host. Handles API auth, SSH sessions, guest upgrades, and logging. |
| `proxmox_batch.py` | Loads `proxmox-hosts.toml`, expands defaults, runs multiple hosts concurrently, and enforces credential checks. |
| `proxmox_config_wizard.py` | Questionary-based editor to add hosts, tweak defaults, and validate manifests before saving. |
| `proxmox_inventory_builder.py` | Discovers VMs/LXCs on a host, verifies SSH, and writes `guest_inventory` entries. |
| `remote_maintenance.py` | Shared SSH helpers (`SSHSession`, guest upgrade orchestration, package manager detection). |
| `Maskfile.md` | `uv run …` helper tasks for linting, tests, and CLI shortcuts. |
| `tests/` | Pytest coverage for batch execution, maintenance workflow, and the wizard helpers. |

## Common Commands
```bash
mask lint          # Ruff lint
mask format        # Ruff format
mask typecheck     # Pyright strict mode
mask test          # pytest suite
mask proxmox:run   # uv run proxmox_maintenance.py ...
mask proxmox:batch # uv run proxmox_batch.py ...
mask proxmox:config    # run the manifest wizard
mask proxmox:inventory # discover guests & update manifest
```
(Each Mask task forwards extra flags to the underlying `uv run …` call.)

## Manifest (`py/proxmox-hosts.toml`)
`proxmox_batch.py` and the wizards share a single manifest schema so defaults and hosts stay versioned with the codebase. Example:

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
ssh.identity_file = "~/.ssh/proxmox-b"
guest.user = "admin"
api.token_env = "PROXMOX_B_TOKEN"
api.secret_env = "PROXMOX_B_SECRET"
dry_run = true
```

Per host you must export the `api.token_env` + `api.secret_env` variables before running batch jobs (for CI use secrets/direnv). Optional keys such as `guest_inventory` are preserved by the wizards even if they are not explicitly documented here.

## CLI Reference
- `proxmox_maintenance.py`: Lifecycle orchestrator for a single node—backs up VMs, drains guests, applies OS upgrades, and reboots while honoring manifest defaults and dry-run semantics.
- `proxmox_batch.py`: Concurrency-aware launcher that reads `proxmox-hosts.toml`, verifies required secrets, and summarizes host results with CI-friendly exit codes.
- `proxmox_config_wizard.py`: Questionary-driven editor for manifests, enabling host add/clone/delete workflows plus validation before persisting without clobbering unknown keys.
- `proxmox_inventory_builder.py`: Guided guest discovery assistant that pulls VM/LXC metadata via the API, validates SSH/guest-agent access, and writes structured `guest_inventory` entries.

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
