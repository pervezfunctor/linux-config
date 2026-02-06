#!/usr/bin/env python3
"""Batch runner for Proxmox maintenance tasks - Legacy Entry Point.

This module provides backward compatibility for the old CLI interface.
New code should use: python -m proxmox_cli batch run

Exit codes:
  0 - every host succeeded
  1 - manifest or configuration error
  3 - one or more hosts failed during maintenance
"""

from __future__ import annotations

import asyncio
from pathlib import Path

import structlog
import typer

from proxmox_cli.core.batch import DEFAULT_CONFIG_PATH, async_run_batch, load_manifest, select_hosts
from proxmox_cli.core.batch_helpers import build_host_options
from proxmox_cli.core.exceptions import HostSelectionError, ManifestError
from proxmox_cli.core.models import BatchDefaults, HostConfig

# Re-export for backward compatibility
__all__ = [
    "DEFAULT_CONFIG_PATH",
    "BatchDefaults",
    "HostConfig",
    "HostSelectionError",
    "ManifestError",
    "async_run_batch",
    "build_host_options",
    "load_manifest",
    "select_hosts",
]

logger = structlog.get_logger(__name__)
app = typer.Typer(add_completion=False, help="Batch runner for Proxmox maintenance tasks.")

_CONFIG_OPTION = typer.Option(
    DEFAULT_CONFIG_PATH,
    "--config",
    "-c",
    help="Path to proxmox hosts manifest",
)
_HOST_OPTION = typer.Option(
    None,
    "--host",
    help="Limit execution to the specified host name (repeatable)",
)
_DRY_RUN_OPTION = typer.Option(
    False,
    "--dry-run",
    help="Force dry-run across every host regardless of manifest",
)
_MAX_HOSTS_OPTION = typer.Option(
    None,
    "--max-hosts",
    min=1,
    help="Process at most N hosts from the filtered list",
)
_VERBOSE_OPTION = typer.Option(False, "--verbose", "-v", help="Enable verbose logging")


def _print_cli_notice() -> None:
    logger.warning(
        "legacy-cli-notice",
        recommendation="Use `python -m proxmox_cli batch run` for the new CLI surface.",
    )


def _resolve_config_path(value: str | Path) -> Path:
    return Path(value).expanduser()


@app.command("run")
def cli_run(
    config: Path = _CONFIG_OPTION,
    host: list[str] | None = _HOST_OPTION,
    dry_run: bool = _DRY_RUN_OPTION,
    max_hosts: int | None = _MAX_HOSTS_OPTION,
    verbose: bool = _VERBOSE_OPTION,
) -> None:
    _print_cli_notice()
    exit_code = asyncio.run(
        async_run_batch(
            config_path=_resolve_config_path(config),
            host_filters=tuple(host or []),
            limit=max_hosts,
            force_dry_run=dry_run,
            verbose=verbose,
        )
    )
    raise typer.Exit(exit_code)


def main() -> None:
    app()


if __name__ == "__main__":
    main()
