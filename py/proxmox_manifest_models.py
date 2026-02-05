"""Shared Pydantic models for proxmox manifest editing helpers."""

from __future__ import annotations

from typing import Any

from pydantic import BaseModel, ConfigDict, Field


class ManifestModel(BaseModel):
    """Base model enabling assignment validation for manifest forms."""

    model_config = ConfigDict(validate_assignment=True)


class DefaultsForm(ManifestModel):
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
    defaults: DefaultsForm = Field(default_factory=DefaultsForm)
    hosts: list[HostForm] = Field(default_factory=_host_list_factory)
    top_level_extras: dict[str, Any] = Field(default_factory=dict)

    @classmethod
    def empty(cls) -> ManifestState:
        return cls()


__all__ = ["DefaultsForm", "HostForm", "ManifestModel", "ManifestState"]
