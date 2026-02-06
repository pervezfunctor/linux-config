"""Shared Pydantic models for proxmox manifest editing helpers - Legacy Entry Point.

This module provides backward compatibility.
New code should use: from proxmox_cli.core.models import ManifestState, DefaultsForm, HostForm
"""

from proxmox_cli.core.models import DefaultsForm, HostForm, ManifestModel, ManifestState

__all__ = ["DefaultsForm", "HostForm", "ManifestModel", "ManifestState"]
