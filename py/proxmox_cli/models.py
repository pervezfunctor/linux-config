"""Pydantic models for Typer CLI options."""

from __future__ import annotations

from pathlib import Path

from pydantic import BaseModel, ConfigDict

# Re-export core models for convenience
from proxmox_cli.core.batch import DEFAULT_CONFIG_PATH
from proxmox_cli.core.models import (
    BatchDefaults,
    DefaultsForm,
    HostConfig,
    HostForm,
    MaintenanceRunOptions,
    ManifestState,
)


class _CLIModel(BaseModel):
    """Base model for CLI options."""

    model_config = ConfigDict(frozen=True)


class BatchOptions(_CLIModel):
    """Options for batch run command."""

    manifest: Path
    hosts: tuple[str, ...]
    limit: int | None
    force_dry_run: bool
    verbose: bool


class WizardOptions(_CLIModel):
    """Options for wizard command."""

    manifest: Path
    verbose: bool


class InventoryOptions(_CLIModel):
    """Options for inventory command."""

    manifest: Path
    host: str | None
    verbose: bool


__all__ = [
    "DEFAULT_CONFIG_PATH",
    "BatchDefaults",
    "BatchOptions",
    "DefaultsForm",
    "HostConfig",
    "HostForm",
    "InventoryOptions",
    "MaintenanceRunOptions",
    "ManifestState",
    "WizardOptions",
]
