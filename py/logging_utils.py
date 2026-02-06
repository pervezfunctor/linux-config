"""Shared logging helpers using structlog + Logfire - Legacy Entry Point.

This module provides backward compatibility.
New code should use: from proxmox_cli.utils import configure_logging
"""

from proxmox_cli.utils.logging import configure_logging

__all__ = ["configure_logging"]
