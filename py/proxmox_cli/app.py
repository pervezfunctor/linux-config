"""Typer CLI entrypoints for Proxmox automation."""

from __future__ import annotations

import asyncio
from pathlib import Path
from typing import Annotated

import typer
from typer import Option

from proxmox_cli.core.batch import DEFAULT_CONFIG_PATH, async_run_batch
from proxmox_cli.core.maintenance import run_with_options
from proxmox_cli.core.models import MaintenanceRunOptions
from proxmox_cli.models import BatchOptions, InventoryOptions, WizardOptions
from proxmox_cli.utils import configure_logging

app = typer.Typer(help="Proxmox maintenance toolkit")


@app.callback()
def main_callback(
    verbose: Annotated[bool, Option("--verbose", "-v", help="Enable verbose logging globally")] = False,
) -> None:
    configure_logging(verbose)


def _manifest_path(value: str | None) -> Path:
    return Path(value).expanduser() if value else DEFAULT_CONFIG_PATH


batch_app = typer.Typer(help="Batch maintenance commands")
app.add_typer(batch_app, name="batch")


@batch_app.command("run", help="Run maintenance across hosts in a manifest")
def batch_run(
    manifest: Annotated[str | None, Option("--manifest", "-m", help="Manifest path")] = None,
    host: Annotated[
        list[str] | None, Option("--host", "-h", help="Limit to host name", show_default=False)
    ] = None,
    limit: Annotated[int | None, Option("--limit", help="Process at most N hosts")] = None,
    force_dry_run: Annotated[bool, Option("--force-dry-run", help="Force dry run")] = False,
    verbose: Annotated[bool, Option("--verbose", help="Enable verbose logging for this run")] = False,
) -> None:
    options = BatchOptions(
        manifest=_manifest_path(manifest),
        hosts=tuple(host or []),
        limit=limit,
        force_dry_run=force_dry_run,
        verbose=verbose,
    )
    exit_code = asyncio.run(
        async_run_batch(
            config_path=options.manifest,
            host_filters=options.hosts,
            limit=options.limit,
            force_dry_run=options.force_dry_run,
            verbose=options.verbose,
        )
    )
    raise typer.Exit(code=exit_code)


wizard_app = typer.Typer(help="Manifest editing wizard")
app.add_typer(wizard_app, name="wizard")


@wizard_app.command("run")
def wizard_run(
    manifest: Annotated[str | None, Option("--manifest", "-m", help="Manifest path")] = None,
    verbose: Annotated[bool, Option("--verbose", help="Verbose logging")] = False,
) -> None:
    import proxmox_config_wizard  # Lazy import to avoid circular dependency
    
    options = WizardOptions(manifest=_manifest_path(manifest), verbose=verbose)
    exit_code = proxmox_config_wizard.run_wizard(options.manifest, verbose=options.verbose)
    raise typer.Exit(code=exit_code)


inventory_app = typer.Typer(help="Inventory management commands")
app.add_typer(inventory_app, name="inventory")


@inventory_app.command("configure")
def inventory_configure(
    manifest: Annotated[str | None, Option("--manifest", "-m", help="Manifest path")] = None,
    host: Annotated[str | None, Option("--host", help="Pre-select host")] = None,
    verbose: Annotated[bool, Option("--verbose", help="Verbose logging")] = False,
    tui: Annotated[bool, Option("--tui", help="Use Textual TUI interface")] = False,
) -> None:
    import proxmox_inventory_builder  # Lazy import to avoid circular dependency
    
    options = InventoryOptions(
        manifest=_manifest_path(manifest),
        host=host,
        verbose=verbose,
    )
    run_options = proxmox_inventory_builder.InventoryRunOptions(
        manifest=options.manifest,
        host=options.host,
        verbose=options.verbose,
    )
    if tui:
        from proxmox_cli.textual_app import run_textual_app

        exit_code = run_textual_app(run_options)
    else:
        exit_code = proxmox_inventory_builder.run_inventory(run_options)
    raise typer.Exit(code=exit_code)


maintenance_app = typer.Typer(help="Single host maintenance")
app.add_typer(maintenance_app, name="maintenance")


@maintenance_app.command("run")
def maintenance_run(
    host: Annotated[str, Option(help="Proxmox host")],
    user: Annotated[str, Option("--user", help="Host SSH user")] = "root",
    identity_file: Annotated[str | None, Option("--identity-file", help="Host identity file")] = None,
    guest_user: Annotated[str, Option("--guest-user", help="Guest SSH user")] = "root",
    guest_identity_file: Annotated[
        str | None,
        Option("--guest-identity-file", help="Guest identity file"),
    ] = None,
    guest_ssh_extra_arg: Annotated[
        list[str] | None,
        Option("--guest-ssh-extra-arg", help="Guest SSH arg", show_default=False),
    ] = None,
    ssh_extra_arg: Annotated[
        list[str] | None,
        Option("--ssh-extra-arg", help="Host SSH arg", show_default=False),
    ] = None,
    max_parallel: Annotated[int, Option("--max-parallel", help="Concurrent guest ops")] = 2,
    dry_run: Annotated[bool, Option("--dry-run", help="Dry run")] = False,
    verbose: Annotated[bool, Option("--verbose", help="Verbose logging")] = False,
) -> None:
    identity_path = Path(identity_file).expanduser() if identity_file else None
    guest_identity_path = Path(guest_identity_file).expanduser() if guest_identity_file else None
    
    configure_logging(verbose)
    
    run_options = MaintenanceRunOptions(
        host=host,
        user=user,
        identity_file=identity_path,
        ssh_extra_args=tuple(ssh_extra_arg or []),
        guest_user=guest_user,
        guest_identity_file=guest_identity_path,
        guest_ssh_extra_args=tuple(guest_ssh_extra_arg or []),
        max_parallel=max_parallel,
        dry_run=dry_run,
    )
    exit_code = asyncio.run(run_with_options(run_options))
    raise typer.Exit(code=exit_code)
