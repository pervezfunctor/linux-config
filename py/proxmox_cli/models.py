"""Pydantic models for Typer CLI options."""

from __future__ import annotations

from collections.abc import Iterable
from pathlib import Path

from pydantic import BaseModel, ConfigDict, Field, field_validator

from proxmox_batch import DEFAULT_CONFIG_PATH


class _BaseOptions(BaseModel):
    model_config = ConfigDict(frozen=True)

    verbose: bool = False


def _expand_manifest(value: str | Path) -> Path:
    path = Path(value)
    return path.expanduser().resolve()


class BatchOptions(_BaseOptions):
    manifest: Path = Field(default=DEFAULT_CONFIG_PATH)
    hosts: tuple[str, ...] = Field(default_factory=tuple)
    limit: int | None = Field(default=None, ge=1)
    force_dry_run: bool = False

    _validate_manifest = field_validator("manifest", mode="before")(_expand_manifest)

    @field_validator("hosts", mode="before")
    @classmethod
    def _coerce_hosts(cls, value: Iterable[str] | str | None) -> tuple[str, ...]:
        if value is None:
            return ()
        if isinstance(value, str):
            return (value,)
        return tuple(value)


class WizardOptions(_BaseOptions):
    manifest: Path = Field(default=DEFAULT_CONFIG_PATH)

    _validate_manifest = field_validator("manifest", mode="before")(_expand_manifest)


class InventoryOptions(_BaseOptions):
    manifest: Path = Field(default=DEFAULT_CONFIG_PATH)
    host: str | None = None

    _validate_manifest = field_validator("manifest", mode="before")(_expand_manifest)


class MaintenanceOptions(_BaseOptions):
    host: str
    user: str = "root"
    identity_file: Path | None = None
    guest_user: str = "root"
    guest_identity_file: Path | None = None
    guest_ssh_extra_args: tuple[str, ...] = Field(default_factory=tuple)
    ssh_extra_args: tuple[str, ...] = Field(default_factory=tuple)
    max_parallel: int = Field(default=2, ge=1)
    dry_run: bool = False

    @field_validator("identity_file", "guest_identity_file", mode="before")
    @classmethod
    def _expand_identity(cls, value: str | Path | None) -> Path | None:
        if value is None:
            return None
        return Path(value).expanduser().resolve()

    @field_validator("ssh_extra_args", "guest_ssh_extra_args", mode="before")
    @classmethod
    def _normalize_args(cls, value: Iterable[str] | str | None) -> tuple[str, ...]:
        if value is None:
            return ()
        if isinstance(value, str):
            return (value,)
        return tuple(value)
