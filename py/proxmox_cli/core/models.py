"""Unified Pydantic models for Proxmox CLI."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, field_validator


def _expand_path(value: str | None) -> str | None:
    """Expand user paths like ~/."""
    if value is None:
        return None
    return str(Path(value).expanduser())


class _BaseModel(BaseModel):
    """Base model with common configuration."""

    model_config = ConfigDict(validate_assignment=True, extra="forbid")


# Batch Processing Models


class BatchDefaults(_BaseModel):
    """Default configuration for batch processing."""

    user: str = "root"
    guest_user: str = "root"
    identity_file: str | None = None
    guest_identity_file: str | None = None
    ssh_extra_args: tuple[str, ...] = Field(default_factory=tuple)
    guest_ssh_extra_args: tuple[str, ...] = Field(default_factory=tuple)
    max_parallel: int = 2
    dry_run: bool = False

    @field_validator("identity_file", "guest_identity_file", mode="before")
    @classmethod
    def _expand_identity(cls, value: str | None) -> str | None:
        return _expand_path(value)

    @field_validator("max_parallel")
    @classmethod
    def _validate_parallel(cls, value: int) -> int:
        if value <= 0:
            raise ValueError("max_parallel must be positive")
        return value


class HostConfig(_BaseModel):
    """Configuration for a single Proxmox host."""

    name: str
    host: str
    user: str
    guest_ssh_extra_args: tuple[str, ...] = Field(default_factory=tuple)
    max_parallel: int
    dry_run: bool

    @field_validator("max_parallel")
    @classmethod
    def _validate_parallel(cls, value: int) -> int:
        if value <= 0:
            raise ValueError("max_parallel must be positive")
        return value


class HostResult(_BaseModel):
    """Result of running maintenance on a single host."""

    name: str
    success: bool
    duration: float
    message: str | None = None


# Maintenance Models


@dataclass(frozen=True)
class MaintenanceRunOptions:
    """Options for running maintenance on a single Proxmox host."""

    host: str
    user: str
    identity_file: Path | None
    ssh_extra_args: tuple[str, ...]
    guest_user: str
    guest_identity_file: Path | None
    guest_ssh_extra_args: tuple[str, ...]
    max_parallel: int
    dry_run: bool


# Manifest Models (for wizard/UI)


class ManifestModel(BaseModel):
    """Base model enabling assignment validation for manifest forms."""

    model_config = ConfigDict(validate_assignment=True)


class DefaultsForm(ManifestModel):
    """Form model for manifest defaults section."""

    user: str = "root"
    guest_user: str = "root"
    identity_file: str | None = None
    guest_identity_file: str | None = None
    ssh_extra_args: list[str] = Field(default_factory=list)
    guest_ssh_extra_args: list[str] = Field(default_factory=list)
    max_parallel: int = 2
    dry_run: bool = False
    extras: dict[str, Any] = Field(default_factory=dict)


class HostForm(ManifestModel):
    """Form model for a single host entry."""

    name: str
    host: str
    user: str | None = None
    guest_ssh_extra_args: list[str] | None = None
    max_parallel: int | None = None
    dry_run: bool | None = None
    extras: dict[str, Any] = Field(default_factory=dict)


def _host_list_factory() -> list[HostForm]:
    return []


class ManifestState(ManifestModel):
    """Complete manifest state for editing."""

    defaults: DefaultsForm = Field(default_factory=DefaultsForm)
    hosts: list[HostForm] = Field(default_factory=_host_list_factory)
    top_level_extras: dict[str, Any] = Field(default_factory=dict)

    @classmethod
    def empty(cls) -> ManifestState:
        return cls()


__all__ = [
    "BatchDefaults",
    "DefaultsForm",
    "HostConfig",
    "HostForm",
    "HostResult",
    "MaintenanceRunOptions",
    "ManifestModel",
    "ManifestState",
]
