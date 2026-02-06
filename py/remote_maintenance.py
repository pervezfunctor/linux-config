"""Reusable SSH helpers for maintaining remote Linux guests - Legacy Entry Point.

This module provides backward compatibility.
New code should use: from proxmox_cli.utils import SSHSession, GuestSSHOptions, etc.
"""

from proxmox_cli.utils.ssh import (
    DEFAULT_SSH_OPTIONS,
    CommandExecutionError,
    CommandResult,
    GuestSSHOptions,
    SSHSession,
    attempt_guest_upgrade,
    build_upgrade_command,
    determine_package_manager,
    parse_os_release,
    prompt_for_alternate_username,
    upgrade_guest_operating_system,
)

__all__ = [
    "DEFAULT_SSH_OPTIONS",
    "CommandExecutionError",
    "CommandResult",
    "GuestSSHOptions",
    "SSHSession",
    "attempt_guest_upgrade",
    "build_upgrade_command",
    "determine_package_manager",
    "parse_os_release",
    "prompt_for_alternate_username",
    "upgrade_guest_operating_system",
]
