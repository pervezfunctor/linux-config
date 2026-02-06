"""Centralized exception hierarchy for Proxmox CLI."""

from __future__ import annotations


class ProxmoxError(Exception):
    """Base exception for all Proxmox CLI errors."""


class ManifestError(ProxmoxError):
    """Raised when the TOML manifest is invalid or cannot be loaded."""


class HostSelectionError(ProxmoxError):
    """Raised when host filters reference unknown entries."""


class ExecutionError(ProxmoxError):
    """Raised when command execution fails."""


class ProxmoxCLIError(ExecutionError):
    """Raised when inventory commands executed via SSH fail."""


class ValidationError(ProxmoxError):
    """Raised when configuration validation fails."""


__all__ = [
    "ExecutionError",
    "HostSelectionError",
    "ManifestError",
    "ProxmoxCLIError",
    "ProxmoxError",
    "ValidationError",
]
