#!/usr/bin/env python3
"""Interactive helper that builds proxmox-hosts manifests from live inventory.

This script performs the following steps:
1. Prompts for (or updates) a host entry in proxmox-hosts.toml.
2. Uses SSH access to discover VMs and containers on the host.
3. Lets operators mark which guests should be managed and capture notes.
4. Persists the collected metadata back to the TOML manifest so proxmox_maintenance can consume it.

The workflow is intentionally verbose to keep operators informed about what is
happening (network calls, SSH checks, etc.).
"""

from __future__ import annotations

import asyncio
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Literal, cast

import questionary
import structlog
import typer
from pydantic import BaseModel, ConfigDict
from questionary import Choice

from logging_utils import configure_logging
from proxmox_batch import ManifestError
from proxmox_maintenance import (
    LXCContainer,
    ProxmoxCLIClient,
    ProxmoxCLIError,
    VirtualMachine,
    shlex_join,
)
from proxmox_manifest import load_manifest_state, write_manifest
from proxmox_manifest_models import DefaultsForm, HostForm, ManifestState
from questionary_prompts import (
    WizardAbort,
    ask_bool,
    ask_csv_list,
    ask_optional_text,
    ask_required_text,
)
from remote_maintenance import CommandExecutionError, SSHSession

LOGGER = structlog.get_logger(__name__)
DEFAULT_CONFIG_PATH = Path(__file__).with_name("proxmox-hosts.toml")
GUEST_INVENTORY_KEY = "guest_inventory"
app = typer.Typer(add_completion=False, help="Interactive helper for building proxmox-hosts manifests.")

_CONFIG_OPTION = typer.Option(
    DEFAULT_CONFIG_PATH,
    "--config",
    "-c",
    help="Path to proxmox-hosts.toml",
)
_HOST_OPTION = typer.Option(None, "--host", help="Pre-select an existing host entry by name")
_VERBOSE_OPTION = typer.Option(False, "--verbose", "-v", help="Enable debug logging output")


def _print_cli_notice() -> None:
    questionary.print("Tip: use `proxmoxctl inventory configure` for the new CLI.", style="bold yellow")


@dataclass(frozen=True)
class InventoryRunOptions:
    manifest: Path
    host: str | None = None
    verbose: bool = False


class _InventoryModel(BaseModel):
    model_config = ConfigDict(validate_assignment=True)


class GuestDiscovery(_InventoryModel):
    kind: Literal["vm", "ct"]
    identifier: str
    name: str
    status: str
    ip: str | None

    @property
    def label(self) -> str:
        prefix = "VM" if self.kind == "vm" else "CT"
        return f"{prefix} {self.name} ({self.identifier})"


class ManagedGuest(_InventoryModel):
    discovery: GuestDiscovery
    managed: bool
    notes: str | None = None
    last_checked: str

    def to_dict(self) -> dict[str, Any]:
        payload: dict[str, Any] = {
            "kind": self.discovery.kind,
            "id": self.discovery.identifier,
            "name": self.discovery.name,
            "status": self.discovery.status,
            "ip": self.discovery.ip,
            "managed": self.managed,
            "last_checked": self.last_checked,
        }
        if self.notes:
            payload["notes"] = self.notes
        return payload


class InventoryError(RuntimeError):
    """Raised when the wizard cannot continue."""


def load_manifest(path: Path) -> ManifestState:
    if path.exists():
        return load_manifest_state(path)
    questionary.print(f"Creating new manifest at {path}", style="bold yellow")
    return ManifestState.empty()


def save_manifest(state: ManifestState, path: Path) -> None:
    write_manifest(state, path)
    questionary.print(f"Updated manifest written to {path}", style="bold green")


def select_host(state: ManifestState, requested: str | None) -> tuple[HostForm, bool]:
    if requested:
        for host in state.hosts:
            if host.name == requested:
                return host, False
        questionary.print(f"Host '{requested}' not found, creating a new entry.", style="bold yellow")
    if not state.hosts:
        questionary.print("Manifest has no hosts yet. Let's add one.", style="bold yellow")
        return create_host_form(state.defaults), True
    choices = [Choice(title=f"Update {host.name}", value=host) for host in state.hosts]
    choices.append(Choice(title="Add a new host", value="__new__"))
    response = questionary.select("Select a host entry", choices=choices).ask()
    if response is None:
        raise WizardAbort()
    if response == "__new__":
        new_host = create_host_form(state.defaults)
        state.hosts.append(new_host)
        return new_host, True
    return response, False


def create_host_form(defaults: DefaultsForm) -> HostForm:
    name = ask_required_text("Host entry name (used as manifest identifier)")
    host = ask_required_text("Proxmox hostname or IP")
    user = ask_optional_text("Proxmox SSH user", default=defaults.user)
    guest_ssh_args = ask_csv_list(
        "Additional ssh args for guest connections",
        current=defaults.guest_ssh_extra_args,
        allow_inherit=False,
        empty_keyword=None,
        keep_current_on_blank=False,
    ) or []
    dry_run = ask_bool("Enable dry-run for this host by default?", default=defaults.dry_run)
    max_parallel_str = ask_optional_text("Max parallel guest actions", default=str(defaults.max_parallel))
    max_parallel = int(max_parallel_str) if max_parallel_str else defaults.max_parallel
    host_form = HostForm(
        name=name,
        host=host,
        user=user,
        guest_ssh_extra_args=guest_ssh_args or None,
        max_parallel=max_parallel,
        dry_run=dry_run,
    )
    return host_form


def expand_optional_path(value: str | None) -> str | None:
    if not value:
        return None
    return str(Path(value).expanduser())


async def discover_inventory(
    host: HostForm,
    defaults: DefaultsForm,
) -> list[GuestDiscovery]:
    host_user = (host.user or defaults.user).strip()
    if not host_user:
        raise InventoryError("Host SSH user is required to discover inventory")
    if not host.host:
        raise InventoryError("Host entry must include a hostname or IP")
    ssh_identity = expand_optional_path(defaults.identity_file)
    ssh_extra_args = tuple(defaults.ssh_extra_args)
    host_session = SSHSession(
        host=host.host,
        user=host_user,
        dry_run=False,
        identity_file=ssh_identity,
        extra_args=ssh_extra_args,
        description=f"proxmox-{host.name}",
    )
    guests: list[GuestDiscovery] = []
    cli_client = ProxmoxCLIClient(host_session)
    try:
        vms = await cli_client.list_vms()
        vm_guests = await _discover_vms(cli_client, vms)
        guests.extend(vm_guests)
        containers = await cli_client.list_containers()
        ct_guests = await _discover_containers(containers, host_session)
        guests.extend(ct_guests)
    except ProxmoxCLIError as exc:
        raise InventoryError(f"Failed to query Proxmox host via SSH: {exc}") from exc
    return guests


async def _discover_vms(cli_client: ProxmoxCLIClient, vms: list[VirtualMachine]) -> list[GuestDiscovery]:
    discoveries: list[GuestDiscovery] = []
    for vm in vms:
        ip = None
        try:
            interfaces = await cli_client.fetch_vm_interfaces(vm.vmid)
            for interface in interfaces:
                for address in interface.ip_addresses:
                    if address.ip_address_type.lower() == "ipv4":
                        ip = address.ip_address
                        break
                if ip:
                    break
        except ProxmoxCLIError as exc:
            LOGGER.warning("Unable to fetch IP for VM %s: %s", vm.vmid, exc)
        discoveries.append(
            GuestDiscovery(kind="vm", identifier=vm.vmid, name=vm.name, status=vm.status, ip=ip)
        )
    return discoveries


async def _discover_containers(
    containers: list[LXCContainer],
    host_session: SSHSession | None,
) -> list[GuestDiscovery]:
    discoveries: list[GuestDiscovery] = []
    for ct in containers:
        ip = None
        if host_session is not None:
            cmd = shlex_join(["pct", "exec", ct.ctid, "--", "hostname", "-I"])
            try:
                result = await host_session.run(cmd, capture_output=True, mutable=False)
                ip = extract_ipv4(result.stdout)
            except CommandExecutionError as exc:
                LOGGER.warning("Unable to fetch IP for CT %s: %s", ct.ctid, exc)
        discoveries.append(
            GuestDiscovery(kind="ct", identifier=ct.ctid, name=ct.name, status=ct.status, ip=ip)
        )
    return discoveries


def extract_ipv4(output: str) -> str | None:
    for token in output.split():
        parts = token.split(".")
        if len(parts) != 4:
            continue
        try:
            if all(0 <= int(part) <= 255 for part in parts):
                return token
        except ValueError:
            continue
    return None


def load_existing_guest_map(host: HostForm) -> dict[tuple[str, str], dict[str, Any]]:
    extras_raw = host.extras.get(GUEST_INVENTORY_KEY)
    if not isinstance(extras_raw, dict):
        return {}
    extras = cast(dict[str, object], extras_raw)
    entries_obj: list[Any] | None = None
    if "entries" in extras:
        candidate: object = extras["entries"]
        if isinstance(candidate, list):
            entries_obj = cast(list[Any], candidate)
    if entries_obj is None:
        return {}
    entries_list: list[dict[str, Any]] = []
    for raw_item in entries_obj:
        if isinstance(raw_item, dict):
            entries_list.append(cast(dict[str, Any], raw_item))
    mapping: dict[tuple[str, str], dict[str, Any]] = {}
    for entry in entries_list:
        kind_obj = entry.get("kind")
        id_obj = entry.get("id")
        if not isinstance(kind_obj, str) or not isinstance(id_obj, str):
            continue
        mapping[(kind_obj, id_obj)] = entry
    return mapping


def configure_guests(
    host: HostForm,
    defaults: DefaultsForm,
    discoveries: list[GuestDiscovery],
) -> list[ManagedGuest]:
    existing_map = load_existing_guest_map(host)
    entries: list[ManagedGuest] = []
    for guest in discoveries:
        existing = existing_map.get((guest.kind, guest.identifier), {})
        manage = bool(existing.get("managed", True))
        manage = ask_bool(f"Manage {guest.label}?", default=manage)
        notes = ask_optional_text("Notes for this guest (optional)", default=existing.get("notes"))
        entry = ManagedGuest(
            discovery=guest,
            managed=manage,
            notes=notes,
            last_checked=datetime.now(UTC).isoformat(),
        )
        entries.append(entry)
    return entries


def update_host_inventory(host: HostForm, entries: list[ManagedGuest]) -> None:
    host.extras[GUEST_INVENTORY_KEY] = {
        "version": 1,
        "updated_at": datetime.now(UTC).isoformat(),
        "entries": [entry.to_dict() for entry in entries],
    }


def run_inventory(options: InventoryRunOptions) -> int:
    configure_logging(options.verbose)
    manifest_path = options.manifest.expanduser()
    try:
        state = load_manifest(manifest_path)
        host, created = select_host(state, options.host)
        if created and host not in state.hosts:
            state.hosts.append(host)
        discoveries = asyncio.run(discover_inventory(host, state.defaults))
        if not discoveries:
            questionary.print("No guests discovered on this host.", style="bold yellow")
        entries = configure_guests(
            host,
            state.defaults,
            discoveries,
        )
        update_host_inventory(host, entries)
        save_manifest(state, manifest_path)
        questionary.print(f"Configured {len(entries)} guests for host {host.name}", style="bold green")
        return 0
    except WizardAbort:
        questionary.print("Aborted by user", style="bold yellow")
        return 1
    except (ManifestError, InventoryError) as exc:
        questionary.print(f"Error: {exc}", style="bold red")
        return 2


def main_from_options(options: InventoryRunOptions) -> int:
    return run_inventory(options)


@app.command("configure")
def cli_configure(
    config: Path = _CONFIG_OPTION,
    host: str | None = _HOST_OPTION,
    verbose: bool = _VERBOSE_OPTION,
) -> None:
    _print_cli_notice()
    options = InventoryRunOptions(
        manifest=config.expanduser(),
        host=host,
        verbose=verbose,
    )
    exit_code = run_inventory(options)
    raise typer.Exit(exit_code)


def main() -> None:
    app()


if __name__ == "__main__":
    main()
