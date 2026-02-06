"""Core batch processing logic for Proxmox maintenance."""

from __future__ import annotations

import time
import tomllib
from collections.abc import Sequence
from pathlib import Path
from typing import Any, TypeGuard, cast

import structlog

from proxmox_cli.core.exceptions import HostSelectionError, ManifestError
from proxmox_cli.core.models import BatchDefaults, HostConfig, HostResult
from proxmox_cli.utils import configure_logging

logger = structlog.get_logger(__name__)

DEFAULT_CONFIG_PATH = Path(__file__).parent.parent.parent / "proxmox-hosts.toml"


def _is_nonstring_sequence(value: object) -> TypeGuard[Sequence[object]]:
    return isinstance(value, Sequence) and not isinstance(value, (str, bytes))


def _ensure_tuple(value: Any) -> tuple[str, ...]:
    """Convert various input types to tuple of strings."""
    if value is None:
        return ()
    if isinstance(value, tuple):
        return tuple(str(item) for item in cast(tuple[object, ...], value))
    if _is_nonstring_sequence(value):
        return tuple(str(item) for item in value)
    raise TypeError("SSH arguments must be a sequence of strings")


def load_manifest(path: Path) -> tuple[BatchDefaults, list[HostConfig]]:
    """Load and validate manifest from TOML file."""
    try:
        with path.open("rb") as handle:
            data: dict[str, Any] = tomllib.load(handle)
    except FileNotFoundError as exc:
        raise ManifestError(f"Manifest file '{path}' was not found") from exc
    except tomllib.TOMLDecodeError as exc:
        raise ManifestError(f"Manifest file '{path}' is invalid: {exc}") from exc

    # Parse defaults section
    defaults_data_raw = data.get("defaults", {})
    if defaults_data_raw and not isinstance(defaults_data_raw, dict):
        raise ManifestError("[defaults] must be a table")
    defaults_data = cast(dict[str, Any], defaults_data_raw)

    # Extract nested values with proper type handling
    user = cast(str, defaults_data.get("user", "root"))
    
    guest_dict = cast(dict[str, Any], defaults_data.get("guest", {}))
    guest_user_raw = defaults_data.get("guest_user") or guest_dict.get("user", "root")
    guest_user = cast(str, guest_user_raw)
    
    ssh_dict = cast(dict[str, Any], defaults_data.get("ssh", {}))
    identity_file_raw = defaults_data.get("identity_file") or ssh_dict.get("identity_file")
    identity_file = cast(str | None, identity_file_raw)
    
    guest_identity_file_raw = defaults_data.get("guest_identity_file") or guest_dict.get("identity_file")
    guest_identity_file = cast(str | None, guest_identity_file_raw)
    
    ssh_extra_args_raw = defaults_data.get("ssh_extra_args") or ssh_dict.get("extra_args")
    
    guest_ssh_dict = cast(dict[str, Any], guest_dict.get("ssh", {}))
    guest_ssh_extra_args_raw = (
        defaults_data.get("guest_ssh_extra_args")
        or guest_dict.get("ssh_extra_args")
        or guest_ssh_dict.get("extra_args")
    )
    
    max_parallel = cast(int, defaults_data.get("max_parallel", 2))
    dry_run = cast(bool, defaults_data.get("dry_run", False))

    try:
        defaults = BatchDefaults(
            user=user,
            guest_user=guest_user,
            identity_file=identity_file,
            guest_identity_file=guest_identity_file,
            ssh_extra_args=_ensure_tuple(ssh_extra_args_raw),
            guest_ssh_extra_args=_ensure_tuple(guest_ssh_extra_args_raw),
            max_parallel=max_parallel,
            dry_run=dry_run,
        )
    except (ValueError, TypeError) as exc:
        raise ManifestError(f"Invalid defaults configuration: {exc}") from exc

    # Parse hosts section
    hosts_data_raw = data.get("hosts")
    if not isinstance(hosts_data_raw, list) or not hosts_data_raw:
        raise ManifestError("Manifest must include a non-empty [[hosts]] list")

    host_configs: list[HostConfig] = []
    seen_names: set[str] = set()

    for entry_raw in hosts_data_raw:
        if not isinstance(entry_raw, dict):
            raise ManifestError("Each [[hosts]] entry must be a table")
        entry = cast(dict[str, Any], entry_raw)

        host_value = entry.get("host")
        if not host_value or not isinstance(host_value, str):
            raise ManifestError("Each host requires a 'host' value")

        name_value = entry.get("name", host_value)
        if not isinstance(name_value, str):
            raise ManifestError(f"Host name must be a string, got {type(name_value).__name__}")

        if name_value in seen_names:
            raise ManifestError(f"Duplicate host name '{name_value}' detected")
        seen_names.add(name_value)

        # Extract user with proper type handling
        entry_ssh_dict = cast(dict[str, Any], entry.get("ssh", {}))
        user_raw = entry.get("user") or entry_ssh_dict.get("user", defaults.user)
        user = cast(str, user_raw)
        
        # Extract guest SSH args
        entry_guest_dict = cast(dict[str, Any], entry.get("guest", {}))
        entry_guest_ssh_dict = cast(dict[str, Any], entry_guest_dict.get("ssh", {}))
        guest_ssh_extra_raw = (
            entry.get("guest_ssh_extra_args")
            or entry_guest_dict.get("ssh_extra_args")
            or entry_guest_ssh_dict.get("extra_args")
        )
        guest_ssh_extra = _ensure_tuple(guest_ssh_extra_raw) or defaults.guest_ssh_extra_args

        max_parallel = cast(int, entry.get("max_parallel", defaults.max_parallel))
        dry_run = cast(bool, entry.get("dry_run", defaults.dry_run))

        try:
            host_configs.append(
                HostConfig(
                    name=name_value,
                    host=host_value,
                    user=user,
                    guest_ssh_extra_args=guest_ssh_extra,
                    max_parallel=max_parallel,
                    dry_run=dry_run,
                )
            )
        except (ValueError, TypeError) as exc:
            raise ManifestError(f"Invalid host configuration for '{name_value}': {exc}") from exc

    return defaults, host_configs


def select_hosts(hosts: Sequence[HostConfig], requested: Sequence[str]) -> list[HostConfig]:
    """Filter hosts by requested names."""
    if not requested:
        return list(hosts)
    name_index = {host.name: host for host in hosts}
    missing = [name for name in requested if name not in name_index]
    if missing:
        raise HostSelectionError(f"Unknown host(s): {', '.join(missing)}")
    return [name_index[name] for name in requested]


async def run_host(
    host: HostConfig,
    defaults: BatchDefaults,
    *,
    force_dry_run: bool,
) -> tuple[bool, str | None]:
    """Run maintenance on a single host."""
    # Import here to avoid circular dependency
    from proxmox_cli.core.maintenance import MaintenanceRunOptions, run_with_options

    options = MaintenanceRunOptions(
        host=host.host,
        user=host.user,
        identity_file=Path(defaults.identity_file) if defaults.identity_file else None,
        ssh_extra_args=defaults.ssh_extra_args,
        guest_user=defaults.guest_user,
        guest_identity_file=Path(defaults.guest_identity_file) if defaults.guest_identity_file else None,
        guest_ssh_extra_args=host.guest_ssh_extra_args,
        max_parallel=host.max_parallel,
        dry_run=force_dry_run or host.dry_run,
    )

    logger.info("maintenance-start", host=host.name, target=host.host)
    try:
        return_code = await run_with_options(options)
    except Exception as exc:  # pragma: no cover - defensive logging path
        logger.exception("maintenance-run-error", host=host.name)
        return False, str(exc)

    if return_code == 0:
        return True, None
    return False, f"proxmox_maintenance exited with status {return_code}"


async def async_run_batch(
    *,
    config_path: Path,
    host_filters: Sequence[str],
    limit: int | None,
    force_dry_run: bool,
    verbose: bool,
) -> int:
    """Run batch maintenance across multiple hosts.
    
    Returns:
        0 - every host succeeded
        1 - manifest or configuration error
        3 - one or more hosts failed during maintenance
    """
    if limit is not None and limit <= 0:
        raise ValueError("Host limit must be greater than zero")

    configure_logging(verbose)

    try:
        defaults, hosts = load_manifest(config_path)
    except ManifestError as exc:
        logger.error("manifest-error", error=str(exc))
        return 1

    try:
        selected_hosts = select_hosts(hosts, host_filters)
    except HostSelectionError as exc:
        logger.error("host-selection-error", error=str(exc))
        return 1

    if limit is not None:
        selected_hosts = selected_hosts[:limit]

    if not selected_hosts:
        logger.warning("no-hosts-selected")
        return 0

    results: list[HostResult] = []
    runtime_failure = False

    for host in selected_hosts:
        start = time.monotonic()
        try:
            success, message = await run_host(
                host,
                defaults,
                force_dry_run=force_dry_run,
            )
        except Exception as exc:  # pragma: no cover - defensive
            runtime_failure = True
            success = False
            message = f"Unexpected failure for {host.name}: {exc}"
            logger.exception("maintenance-uncaught-error", host=host.name)

        duration = time.monotonic() - start
        results.append(HostResult(name=host.name, success=success, duration=duration, message=message))

        if success:
            logger.info("host-success", host=host.name, duration_sec=duration)
        else:
            logger.error(
                "host-failed",
                host=host.name,
                duration_sec=duration,
                details=message or "no details",
            )

    if runtime_failure or any(not result.success for result in results):
        return 3
    return 0


__all__ = [
    "DEFAULT_CONFIG_PATH",
    "async_run_batch",
    "load_manifest",
    "run_host",
    "select_hosts",
]
