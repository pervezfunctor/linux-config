#!/usr/bin/env python3
"""Proxmox fleet maintenance helper - Legacy Entry Point.

This module provides backward compatibility for the old CLI interface.
New code should use: python -m proxmox_cli maintenance run
"""

from __future__ import annotations

import asyncio
from pathlib import Path

import structlog
import typer

from proxmox_cli.core.exceptions import ProxmoxCLIError
from proxmox_cli.core.maintenance import (
    LXCContainer,
    ProxmoxCLIClient,
    VirtualMachine,
    run_with_options,
    shlex_join,
)
from proxmox_cli.core.models import MaintenanceRunOptions
from proxmox_cli.utils import SSHSession, configure_logging

# Re-export for backward compatibility
__all__ = [
    "LXCContainer",
    "MaintenanceRunOptions",
    "ProxmoxCLIClient",
    "ProxmoxCLIError",
    "SSHSession",
    "VirtualMachine",
    "ensure_valid_host_argument",
    "run_with_options",
    "shlex_join",
]

logger = structlog.get_logger(__name__)
app = typer.Typer(add_completion=False, help="Proxmox guest lifecycle maintenance helper.")


def _print_cli_notice() -> None:
    logger.warning(
        "legacy-cli-notice",
        recommendation="Use `python -m proxmox_cli maintenance run` for the consolidated CLI.",
    )


def _expand_optional_path(value: str | Path | None) -> Path | None:
    if value is None:
        return None
    if isinstance(value, Path):
        return value.expanduser()
    return Path(value).expanduser()


def ensure_valid_host_argument(host: str) -> str:
    trimmed = (host or "").strip()
    if not trimmed:
        raise ValueError("Host/IP address is required (example: proxmox.example.com)")
    if trimmed.startswith("-"):
        raise ValueError(
            "Host parameter appears missing. Provide the Proxmox host before options, e.g. "
            "`proxmox_maintenance proxmox.example --dry-run`. "
            "To show help, run without the extra `--` (example: `proxmox_maintenance --help`)."
        )
    return trimmed


def _host_argument(value: str) -> str:
    try:
        return ensure_valid_host_argument(value)
    except ValueError as exc:
        raise typer.BadParameter(str(exc)) from exc


_HOST_ARGUMENT = typer.Argument(
    ...,
    help="Proxmox host IPv4/IPv6 or DNS",
    callback=_host_argument,
)
_USER_OPTION = typer.Option("root", "--user", "-u", help="Proxmox SSH user")
_IDENTITY_FILE_OPTION = typer.Option(
    None,
    "--identity-file",
    help="SSH identity for Proxmox host",
)
_GUEST_USER_OPTION = typer.Option("root", "--guest-user", help="Guest SSH user")
_GUEST_IDENTITY_FILE_OPTION = typer.Option(
    None,
    "--guest-identity-file",
    help="Guest SSH identity file",
)
_GUEST_SSH_EXTRA_ARG_OPTION = typer.Option(
    None,
    "--guest-ssh-extra-arg",
    help="Additional ssh arguments for guest connections (repeatable)",
)
_SSH_EXTRA_ARG_OPTION = typer.Option(
    None,
    "--ssh-extra-arg",
    help="Additional ssh arguments for Proxmox host connection (repeatable)",
)
_MAX_PARALLEL_OPTION = typer.Option(
    2,
    "--max-parallel",
    min=1,
    help="Maximum concurrent guest operations",
)
_DRY_RUN_OPTION = typer.Option(False, "--dry-run", help="Log actions without changing state")
_VERBOSE_OPTION = typer.Option(False, "--verbose", "-v", help="Enable debug logging")


@app.command("run", no_args_is_help=True)
def cli_run(
    host: str = _HOST_ARGUMENT,
    user: str = _USER_OPTION,
    identity_file: Path | None = _IDENTITY_FILE_OPTION,
    guest_user: str = _GUEST_USER_OPTION,
    guest_identity_file: Path | None = _GUEST_IDENTITY_FILE_OPTION,
    guest_ssh_extra_arg: list[str] | None = _GUEST_SSH_EXTRA_ARG_OPTION,
    ssh_extra_arg: list[str] | None = _SSH_EXTRA_ARG_OPTION,
    max_parallel: int = _MAX_PARALLEL_OPTION,
    dry_run: bool = _DRY_RUN_OPTION,
    verbose: bool = _VERBOSE_OPTION,
) -> None:
    _print_cli_notice()
    configure_logging(verbose)
    options = MaintenanceRunOptions(
        host=host,
        user=user,
        identity_file=_expand_optional_path(identity_file),
        ssh_extra_args=tuple(ssh_extra_arg or []),
        guest_user=guest_user,
        guest_identity_file=_expand_optional_path(guest_identity_file),
        guest_ssh_extra_args=tuple(guest_ssh_extra_arg or []),
        max_parallel=max_parallel,
        dry_run=dry_run,
    )
    exit_code = asyncio.run(run_with_options(options))
    raise typer.Exit(exit_code)


def main() -> None:
    app()


if __name__ == "__main__":
    main()
