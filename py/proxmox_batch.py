#!/usr/bin/env python3
"""Batch runner for Proxmox maintenance tasks.

Exit codes:
  0 - every host succeeded
  1 - manifest or configuration error
  3 - one or more hosts failed during maintenance
"""

from __future__ import annotations

import asyncio
import time
import tomllib
from collections.abc import Iterable, Mapping, Sequence
from pathlib import Path
from typing import Any, TypeGuard, cast

import structlog
import typer
from pydantic import BaseModel, ConfigDict, Field, field_validator

from logging_utils import configure_logging
from proxmox_maintenance import (
    MaintenanceRunOptions,
    run_with_options as run_maintenance_with_options,
)

logger = structlog.get_logger(__name__)
app = typer.Typer(add_completion=False, help="Batch runner for Proxmox maintenance tasks.")

DEFAULT_CONFIG_PATH = Path(__file__).with_name("proxmox-hosts.toml")

_CONFIG_OPTION = typer.Option(
    DEFAULT_CONFIG_PATH,
    "--config",
    "-c",
    help="Path to proxmox hosts manifest",
)
_HOST_OPTION = typer.Option(
    None,
    "--host",
    help="Limit execution to the specified host name (repeatable)",
)
_DRY_RUN_OPTION = typer.Option(
    False,
    "--dry-run",
    help="Force dry-run across every host regardless of manifest",
)
_MAX_HOSTS_OPTION = typer.Option(
    None,
    "--max-hosts",
    min=1,
    help="Process at most N hosts from the filtered list",
)
_VERBOSE_OPTION = typer.Option(False, "--verbose", "-v", help="Enable verbose logging")


def _print_cli_notice() -> None:
    logger.warning(
        "legacy-cli-notice",
        recommendation="Use `proxmoxctl batch run` for the new CLI surface.",
    )


class ManifestError(RuntimeError):
    """Raised when the TOML manifest is invalid."""


class HostSelectionError(ValueError):
    """Raised when host filters reference unknown entries."""


def _is_str_mapping(value: Any) -> TypeGuard[Mapping[str, Any]]:
    return isinstance(value, Mapping)


def _is_nonstring_sequence(value: object) -> TypeGuard[Sequence[object]]:
    return isinstance(value, Sequence) and not isinstance(value, (str, bytes))


def _expand_path(value: str | None) -> str | None:
    if value is None:
        return None
    return str(Path(value).expanduser())


class _Model(BaseModel):
    model_config = ConfigDict(validate_assignment=True, extra="forbid")


class BatchDefaults(_Model):
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

    @field_validator("ssh_extra_args", "guest_ssh_extra_args", mode="before")
    @classmethod
    def _ensure_tuple(cls, value: Any) -> tuple[str, ...]:
        if value is None:
            return ()
        if isinstance(value, tuple):
            return tuple(str(item) for item in cast(tuple[object, ...], value))
        if _is_nonstring_sequence(value):
            return tuple(str(item) for item in value)
        raise TypeError("SSH arguments must be a sequence of strings")

    @field_validator("max_parallel")
    @classmethod
    def _validate_parallel(cls, value: int) -> int:
        if value <= 0:
            raise ValueError("max_parallel must be positive")
        return value


class HostConfig(_Model):
    name: str
    host: str
    user: str
    guest_ssh_extra_args: tuple[str, ...] = Field(default_factory=tuple)
    max_parallel: int
    dry_run: bool

    @field_validator("guest_ssh_extra_args", mode="before")
    @classmethod
    def _ensure_tuple(cls, value: Any) -> tuple[str, ...]:
        if value is None:
            return ()
        if isinstance(value, tuple):
            return tuple(str(item) for item in cast(tuple[object, ...], value))
        if _is_nonstring_sequence(value):
            return tuple(str(item) for item in value)
        raise TypeError("SSH arguments must be a sequence of strings")

    @field_validator("max_parallel")
    @classmethod
    def _validate_parallel(cls, value: int) -> int:
        if value <= 0:
            raise ValueError("max_parallel must be positive")
        return value


class HostResult(_Model):
    name: str
    success: bool
    duration: float
    message: str | None = None


def _lookup(mapping: Mapping[str, Any], dotted_path: str) -> Any | None:
    current: Any = mapping
    for segment in dotted_path.split("."):
        if not _is_str_mapping(current):
            return None
        next_value = current.get(segment)
        if next_value is None:
            return None
        current = next_value
    return current


def _first_value(mapping: Mapping[str, Any], paths: Iterable[str]) -> Any | None:
    for path in paths:
        value = _lookup(mapping, path)
        if value is not None:
            return value
    return None


def _expect_str(value: object, label: str) -> str:
    if isinstance(value, str):
        return value
    raise ManifestError(f"Expected string for '{label}', got {type(value).__name__}")


def _expect_bool(value: object, label: str) -> bool:
    if isinstance(value, bool):
        return value
    raise ManifestError(f"Expected boolean for '{label}', got {type(value).__name__}")


def _expect_int(value: object, label: str) -> int:
    if isinstance(value, int):
        return value
    raise ManifestError(f"Expected integer for '{label}', got {type(value).__name__}")


def _expect_str_list(value: object, label: str) -> tuple[str, ...]:
    if isinstance(value, str):
        return (value,)
    if _is_nonstring_sequence(value):
        return tuple(str(item) for item in value)
    raise ManifestError(f"Expected string list for '{label}', got {type(value).__name__}")


def _get_str(mapping: Mapping[str, Any], *paths: str) -> str | None:
    raw = _first_value(mapping, paths)
    if raw is None:
        return None
    return _expect_str(raw, paths[0])


def _get_bool(mapping: Mapping[str, Any], *paths: str) -> bool | None:
    raw = _first_value(mapping, paths)
    if raw is None:
        return None
    return _expect_bool(raw, paths[0])


def _get_int(mapping: Mapping[str, Any], *paths: str) -> int | None:
    raw = _first_value(mapping, paths)
    if raw is None:
        return None
    return _expect_int(raw, paths[0])


def _get_str_list(mapping: Mapping[str, Any], *paths: str) -> tuple[str, ...] | None:
    raw = _first_value(mapping, paths)
    if raw is None:
        return None
    return _expect_str_list(raw, paths[0])


def load_manifest(path: Path) -> tuple[BatchDefaults, list[HostConfig]]:
    try:
        with path.open("rb") as handle:
            data: dict[str, Any] = tomllib.load(handle)
    except FileNotFoundError as exc:
        raise ManifestError(f"Manifest file '{path}' was not found") from exc
    except tomllib.TOMLDecodeError as exc:
        raise ManifestError(f"Manifest file '{path}' is invalid: {exc}") from exc

    defaults_data = data.get("defaults", {})
    if defaults_data and not isinstance(defaults_data, Mapping):
        raise ManifestError("[defaults] must be a table")

    defaults_mapping: Mapping[str, Any] = (
        cast(Mapping[str, Any], defaults_data) if isinstance(defaults_data, Mapping) else {}
    )
    defaults = BatchDefaults(
        user=_get_str(defaults_mapping, "user") or "root",
        guest_user=_get_str(defaults_mapping, "guest_user", "guest.user") or "root",
        identity_file=_expand_path(_get_str(defaults_mapping, "identity_file", "ssh.identity_file")),
        guest_identity_file=_expand_path(
            _get_str(defaults_mapping, "guest_identity_file", "guest.identity_file")
        ),
        ssh_extra_args=_get_str_list(defaults_mapping, "ssh_extra_args", "ssh.extra_args") or (),
        guest_ssh_extra_args=_get_str_list(
            defaults_mapping,
            "guest_ssh_extra_args",
            "guest.ssh_extra_args",
            "guest.ssh.extra_args",
        )
        or (),
        max_parallel=_get_int(defaults_mapping, "max_parallel") or 2,
        dry_run=_get_bool(defaults_mapping, "dry_run") or False,
    )

    hosts_data_raw_obj = data.get("hosts")
    if not isinstance(hosts_data_raw_obj, list) or not hosts_data_raw_obj:
        raise ManifestError("Manifest must include a non-empty [[hosts]] list")

    hosts_data: list[Any] = cast(list[Any], hosts_data_raw_obj)
    host_entries: list[Mapping[str, Any]] = []
    for entry in hosts_data:
        if not isinstance(entry, Mapping):
            raise ManifestError("Each [[hosts]] entry must be a table")
        host_entries.append(cast(Mapping[str, Any], entry))

    host_configs: list[HostConfig] = []
    seen_names: set[str] = set()
    for entry_mapping in host_entries:
        host_value = _get_str(entry_mapping, "host")
        if not host_value:
            raise ManifestError("Each host requires a 'host' value")
        name_value = _get_str(entry_mapping, "name") or host_value
        if name_value in seen_names:
            raise ManifestError(f"Duplicate host name '{name_value}' detected")
        seen_names.add(name_value)

        user = _get_str(entry_mapping, "user", "ssh.user") or defaults.user
        guest_ssh_extra = (
            _get_str_list(
                entry_mapping,
                "guest_ssh_extra_args",
                "guest.ssh_extra_args",
                "guest.ssh.extra_args",
            )
            or defaults.guest_ssh_extra_args
        )
        max_parallel = _get_int(entry_mapping, "max_parallel") or defaults.max_parallel
        dry_run = _get_bool(entry_mapping, "dry_run")
        if dry_run is None:
            dry_run = defaults.dry_run

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
    return defaults, host_configs


def select_hosts(hosts: Sequence[HostConfig], requested: Sequence[str]) -> list[HostConfig]:
    if not requested:
        return list(hosts)
    name_index = {host.name: host for host in hosts}
    missing = [name for name in requested if name not in name_index]
    if missing:
        raise ValueError(f"Unknown host(s): {', '.join(missing)}")
    return [name_index[name] for name in requested]


def _optional_path(value: str | None) -> Path | None:
    if value is None:
        return None
    return Path(value)


def build_host_options(
    host: HostConfig,
    defaults: BatchDefaults,
    *,
    force_dry_run: bool,
) -> MaintenanceRunOptions:
    return MaintenanceRunOptions(
        host=host.host,
        user=host.user,
        identity_file=_optional_path(defaults.identity_file),
        ssh_extra_args=defaults.ssh_extra_args,
        guest_user=defaults.guest_user,
        guest_identity_file=_optional_path(defaults.guest_identity_file),
        guest_ssh_extra_args=host.guest_ssh_extra_args,
        max_parallel=host.max_parallel,
        dry_run=force_dry_run or host.dry_run,
    )


async def run_host(
    host: HostConfig,
    defaults: BatchDefaults,
    *,
    force_dry_run: bool,
) -> tuple[bool, str | None]:
    options = build_host_options(host, defaults, force_dry_run=force_dry_run)
    logger.info("maintenance-start", host=host.name, target=host.host)
    try:
        return_code = await run_maintenance_with_options(options)
    except Exception as exc:  # pragma: no cover - defensive logging path
        logger.exception("maintenance-run-error", host=host.name)
        return False, str(exc)
    if return_code == 0:
        return True, None
    return False, f"proxmox_maintenance exited with status {return_code}"


def _resolve_config_path(value: str | Path) -> Path:
    return Path(value).expanduser()


async def async_run_batch(
    *,
    config_path: Path,
    host_filters: Sequence[str],
    limit: int | None,
    force_dry_run: bool,
    verbose: bool,
) -> int:
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
    except ValueError as exc:
        raise HostSelectionError(str(exc)) from exc

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


@app.command("run")
def cli_run(
    config: Path = _CONFIG_OPTION,
    host: list[str] | None = _HOST_OPTION,
    dry_run: bool = _DRY_RUN_OPTION,
    max_hosts: int | None = _MAX_HOSTS_OPTION,
    verbose: bool = _VERBOSE_OPTION,
) -> None:
    _print_cli_notice()
    exit_code = asyncio.run(
        async_run_batch(
            config_path=_resolve_config_path(config),
            host_filters=tuple(host or []),
            limit=max_hosts,
            force_dry_run=dry_run,
            verbose=verbose,
        )
    )
    raise typer.Exit(exit_code)


def main() -> None:
    app()


if __name__ == "__main__":
    main()
