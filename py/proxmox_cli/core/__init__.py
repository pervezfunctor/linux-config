"""Core business logic for Proxmox automation."""

from proxmox_cli.core.batch import async_run_batch, load_manifest, select_hosts
from proxmox_cli.core.exceptions import (
    ExecutionError,
    HostSelectionError,
    ManifestError,
    ProxmoxCLIError,
    ProxmoxError,
)
from proxmox_cli.core.maintenance import (
    ProxmoxAgent,
    ProxmoxCLIClient,
    run_with_options,
)
from proxmox_cli.core.models import (
    BatchDefaults,
    HostConfig,
    MaintenanceRunOptions,
)

__all__ = [
    "BatchDefaults",
    "ExecutionError",
    "HostConfig",
    "HostSelectionError",
    "MaintenanceRunOptions",
    "ManifestError",
    "ProxmoxAgent",
    "ProxmoxCLIClient",
    "ProxmoxCLIError",
    "ProxmoxError",
    "async_run_batch",
    "load_manifest",
    "run_with_options",
    "select_hosts",
]
