"""Reusable helpers for reading, validating, and writing Proxmox manifests."""

from __future__ import annotations

import contextlib
import copy
import os
import tempfile
import tomllib
from collections.abc import Callable
from pathlib import Path
from typing import Any, cast

import structlog
import tomli_w

import proxmox_batch
from proxmox_batch import ManifestError
from proxmox_manifest_models import DefaultsForm, HostForm, ManifestState

LOGGER = structlog.get_logger(__name__)


def _to_mutable(value: Any) -> Any:
    if isinstance(value, dict):
        dict_value = cast(dict[str, Any], value)
        result: dict[str, Any] = {}
        for key, item in dict_value.items():
            result[key] = _to_mutable(item)
        return result
    if isinstance(value, list):
        return [_to_mutable(item) for item in cast(list[Any], value)]
    return value


def _pop_path(mapping: dict[str, Any], path: str) -> tuple[Any | None, bool]:
    segments = path.split(".")
    parents: list[tuple[dict[str, Any], str]] = []
    current = mapping
    for segment in segments[:-1]:
        next_value = current.get(segment)
        if not isinstance(next_value, dict):
            return None, False
        parents.append((current, segment))
        current = cast(dict[str, Any], next_value)
    last = segments[-1]
    if last not in current:
        return None, False
    result = current.pop(last)
    for parent, key in reversed(parents):
        child = parent.get(key)
        if isinstance(child, dict) and not child:
            parent.pop(key)
        else:
            break
    return result, True


def _set_path(mapping: dict[str, Any], path: str, value: Any) -> None:
    segments = path.split(".")
    current = mapping
    for segment in segments[:-1]:
        next_value = current.get(segment)
        if not isinstance(next_value, dict):
            next_value = {}
            current[segment] = next_value
        current = cast(dict[str, Any], next_value)
    current[segments[-1]] = value


def _expect_type(value: Any, label: str, validator: Callable[[Any], bool], type_name: str) -> Any:
    if validator(value):
        return value
    raise ManifestError(f"Expected {type_name} for '{label}', got {type(value).__name__}")


def _expect_str(value: Any, label: str) -> str:
    return _expect_type(value, label, lambda v: isinstance(v, str), "string")


def _expect_bool(value: Any, label: str) -> bool:
    return _expect_type(value, label, lambda v: isinstance(v, bool), "boolean")


def _expect_int(value: Any, label: str) -> int:
    return _expect_type(value, label, lambda v: isinstance(v, int), "integer")


def _expect_str_list(value: Any, label: str) -> list[str]:
    if isinstance(value, str):
        return [value]
    if isinstance(value, list):
        return [str(item) for item in cast(list[Any], value)]
    raise ManifestError(f"Expected string list for '{label}', got {type(value).__name__}")


def _extract(mapping: dict[str, Any], *paths: str) -> tuple[Any | None, bool, str | None]:
    for path in paths:
        value, found = _pop_path(mapping, path)
        if found:
            return value, True, path
    return None, False, None


def _load_defaults(defaults_raw: dict[str, Any]) -> DefaultsForm:
    working = cast(dict[str, Any], _to_mutable(defaults_raw))
    user_value, found, _ = _extract(working, "user")
    user = _expect_str(user_value, "defaults.user") if found else "root"

    guest_user_value, found, _ = _extract(working, "guest_user", "guest.user")
    guest_user = _expect_str(guest_user_value, "defaults.guest_user") if found else "root"

    identity_value, found, _ = _extract(working, "identity_file", "ssh.identity_file")
    identity_file = _expect_str(identity_value, "defaults.identity_file") if found else None

    guest_identity_value, found, _ = _extract(
        working,
        "guest_identity_file",
        "guest.identity_file",
    )
    guest_identity_file = _expect_str(guest_identity_value, "defaults.guest_identity_file") if found else None

    ssh_extra_value, found, _ = _extract(working, "ssh_extra_args", "ssh.extra_args")
    ssh_extra_args = _expect_str_list(ssh_extra_value, "defaults.ssh_extra_args") if found else []

    guest_ssh_value, found, _ = _extract(
        working,
        "guest_ssh_extra_args",
        "guest.ssh_extra_args",
        "guest.ssh.extra_args",
    )
    guest_ssh_extra_args = _expect_str_list(guest_ssh_value, "defaults.guest_ssh_extra_args") if found else []

    max_parallel_value, found, _ = _extract(working, "max_parallel")
    max_parallel = _expect_int(max_parallel_value, "defaults.max_parallel") if found else 2

    dry_run_value, found, _ = _extract(working, "dry_run")
    dry_run = _expect_bool(dry_run_value, "defaults.dry_run") if found else False

    return DefaultsForm(
        user=user,
        guest_user=guest_user,
        identity_file=identity_file,
        guest_identity_file=guest_identity_file,
        ssh_extra_args=ssh_extra_args,
        guest_ssh_extra_args=guest_ssh_extra_args,
        max_parallel=max_parallel,
        dry_run=dry_run,
        extras=working,
    )


def _load_host(entry_raw: dict[str, Any]) -> HostForm:
    working = cast(dict[str, Any], _to_mutable(entry_raw))

    name_value, found, _ = _extract(working, "name")
    name = _expect_str(name_value, "hosts.name") if found else None

    host_value, host_found, _ = _extract(working, "host")
    if not host_found:
        raise ManifestError("Each host requires a 'host' value")
    host = _expect_str(host_value, "hosts.host")

    if name is None:
        name = host

    def _optional_str(*paths: str) -> str | None:
        value, found, _ = _extract(working, *paths)
        return _expect_str(value, paths[0]) if found else None

    def _optional_int(*paths: str) -> int | None:
        value, found, _ = _extract(working, *paths)
        return _expect_int(value, paths[0]) if found else None

    def _optional_bool(*paths: str) -> bool | None:
        value, found, _ = _extract(working, *paths)
        return _expect_bool(value, paths[0]) if found else None

    def _optional_list(*paths: str) -> list[str] | None:
        value, found, _ = _extract(working, *paths)
        return _expect_str_list(value, paths[0]) if found else None

    _extract(working, "identity_file", "ssh.identity_file")
    _extract(working, "ssh_extra_args", "ssh.extra_args")
    _extract(working, "guest_user", "guest.user")
    _extract(working, "guest_identity_file", "guest.identity_file")

    return HostForm(
        name=name,
        host=host,
        user=_optional_str("user", "ssh.user"),
        guest_ssh_extra_args=_optional_list(
            "guest_ssh_extra_args",
            "guest.ssh_extra_args",
            "guest.ssh.extra_args",
        ),
        max_parallel=_optional_int("max_parallel"),
        dry_run=_optional_bool("dry_run"),
        extras=working,
    )


def load_manifest_state(path: Path) -> ManifestState:
    with path.open("rb") as handle:
        raw_data: Any = tomllib.load(handle)

    if raw_data is None:
        raw_mapping: dict[str, Any] = {}
    elif isinstance(raw_data, dict):
        raw_mapping = cast(dict[str, Any], raw_data)
    else:
        raise ManifestError("Manifest root must be a table")

    defaults_section = raw_mapping.get("defaults")
    if defaults_section is None:
        defaults_raw: dict[str, Any] = {}
    elif isinstance(defaults_section, dict):
        defaults_raw = cast(dict[str, Any], defaults_section)
    else:
        raise ManifestError("[defaults] must be a table")
    defaults = _load_defaults(defaults_raw)

    hosts_entries: list[HostForm] = []
    hosts_section = raw_mapping.get("hosts")
    if hosts_section is None:
        hosts_entries = []
    elif isinstance(hosts_section, list):
        host_entries_raw = cast(list[Any], hosts_section)
        for entry in host_entries_raw:
            if not isinstance(entry, dict):
                raise ManifestError("Each [[hosts]] entry must be a table")
            host_entry = cast(dict[str, Any], entry)
            hosts_entries.append(_load_host(host_entry))
    else:
        raise ManifestError("[[hosts]] must be an array of tables")

    top_level_extras: dict[str, Any] = {
        key: _to_mutable(value) for key, value in raw_mapping.items() if key not in {"defaults", "hosts"}
    }

    return ManifestState(defaults=defaults, hosts=hosts_entries, top_level_extras=top_level_extras)


def _defaults_to_dict(defaults: DefaultsForm) -> dict[str, Any]:
    mapping = copy.deepcopy(defaults.extras)

    def _set_optional(path: str, value: Any | None) -> None:
        if value is None:
            _pop_path(mapping, path)
        else:
            _set_path(mapping, path, value)

    _set_path(mapping, "user", defaults.user)
    _set_path(mapping, "guest_user", defaults.guest_user)
    _set_optional("identity_file", defaults.identity_file)
    _set_optional("guest_identity_file", defaults.guest_identity_file)
    _set_path(mapping, "ssh_extra_args", list(defaults.ssh_extra_args))
    _set_path(mapping, "guest_ssh_extra_args", list(defaults.guest_ssh_extra_args))
    _set_path(mapping, "max_parallel", defaults.max_parallel)
    _set_path(mapping, "dry_run", defaults.dry_run)
    return mapping


def _host_to_dict(host: HostForm) -> dict[str, Any]:
    mapping = copy.deepcopy(host.extras)

    def _set_optional(path: str, value: Any | None) -> None:
        if value is None:
            _pop_path(mapping, path)
        else:
            _set_path(mapping, path, value)

    _set_path(mapping, "name", host.name)
    _set_path(mapping, "host", host.host)
    _set_optional("user", host.user)
    _set_optional(
        "guest_ssh_extra_args",
        None if host.guest_ssh_extra_args is None else list(host.guest_ssh_extra_args),
    )
    _set_optional("max_parallel", host.max_parallel)
    _set_optional("dry_run", host.dry_run)
    return mapping


def manifest_state_to_dict(state: ManifestState) -> dict[str, Any]:
    data = copy.deepcopy(state.top_level_extras)
    data["defaults"] = _defaults_to_dict(state.defaults)
    data["hosts"] = [_host_to_dict(host) for host in state.hosts]
    return data


def _ensure_proxmox_compat(payload: str) -> None:
    with tempfile.NamedTemporaryFile("w+", encoding="utf-8", delete=False) as handle:
        handle.write(payload)
        temp_path = Path(handle.name)
    try:
        proxmox_batch.load_manifest(temp_path)
    finally:
        with contextlib.suppress(FileNotFoundError):
            temp_path.unlink()


def write_manifest(state: ManifestState, path: Path) -> None:
    validate_state(state)
    data = manifest_state_to_dict(state)
    payload = tomli_w.dumps(data)
    _ensure_proxmox_compat(payload)
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=str(path.parent), delete=False) as handle:
        handle.write(payload)
        temp_name = Path(handle.name)
    os.replace(temp_name, path)
    LOGGER.info("manifest-saved", path=str(path))


def validate_state(state: ManifestState) -> None:
    if state.defaults.max_parallel <= 0:
        raise ManifestError("defaults.max_parallel must be greater than zero")

    names: set[str] = set()
    if not state.hosts:
        raise ManifestError("Manifest must include at least one host")

    for host in state.hosts:
        if not host.name:
            raise ManifestError("Host entries require a name")
        if host.name in names:
            raise ManifestError(f"Duplicate host name '{host.name}' detected")
        names.add(host.name)
        if not host.host:
            raise ManifestError(f"Host '{host.name}' is missing a host value")
        if host.max_parallel is not None and host.max_parallel <= 0:
            raise ManifestError(f"Host '{host.name}' max_parallel must be greater than zero")


__all__ = [
    "DefaultsForm",
    "HostForm",
    "ManifestState",
    "load_manifest_state",
    "manifest_state_to_dict",
    "validate_state",
    "write_manifest",
]
