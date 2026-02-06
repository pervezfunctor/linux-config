"""Helper function for building MaintenanceRunOptions from host config.

This function was part of the original batch.py but was removed during refactoring.
It's recreated here for backward compatibility with tests.
"""

from __future__ import annotations

from pathlib import Path

from proxmox_cli.core.models import BatchDefaults, HostConfig, MaintenanceRunOptions


def build_host_options(
    host: HostConfig,
    defaults: BatchDefaults,
    *,
    force_dry_run: bool,
) -> MaintenanceRunOptions:
    """Build MaintenanceRunOptions from host config and defaults.
    
    This is a helper function for tests and backward compatibility.
    """
    return MaintenanceRunOptions(
        host=host.host,
        user=host.user,
        identity_file=Path(defaults.identity_file) if defaults.identity_file else None,
        ssh_extra_args=defaults.ssh_extra_args,
        guest_user=defaults.guest_user,
        guest_identity_file=Path(defaults.guest_identity_file) if defaults.guest_identity_file else None,
        guest_ssh_extra_args=host.guest_ssh_extra_args,
        max_parallel=host.max_parallel,
        dry_run=force_dry_run or host.dry_run,
    )


__all__ = ["build_host_options"]
