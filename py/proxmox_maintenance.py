#!/usr/bin/env python3
"""Proxmox fleet maintenance helper."""

from __future__ import annotations

import asyncio
import json
import shlex
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Protocol, cast

import structlog
import typer
from pydantic import BaseModel, ConfigDict, Field, TypeAdapter, ValidationError

from logging_utils import configure_logging
from remote_maintenance import (
    CommandExecutionError,
    GuestSSHOptions,
    SSHSession,
    attempt_guest_upgrade,
    build_upgrade_command,
    determine_package_manager,
    parse_os_release,
)

logger = structlog.get_logger(__name__)
app = typer.Typer(add_completion=False, help="Proxmox guest lifecycle maintenance helper.")


@dataclass(frozen=True)
class MaintenanceRunOptions:
    host: str
    user: str
    identity_file: Path | None
    ssh_extra_args: tuple[str, ...]
    guest_user: str
    guest_identity_file: Path | None
    guest_ssh_extra_args: tuple[str, ...]
    max_parallel: int
    dry_run: bool


def _print_cli_notice() -> None:
    logger.warning(
        "legacy-cli-notice",
        recommendation="Use `proxmoxctl maintenance run` for the consolidated CLI.",
    )
    

def _expand_optional_path(value: str | Path | None) -> Path | None:
    if value is None:
        return None
    if isinstance(value, Path):
        return value.expanduser()
    return Path(value).expanduser()


class _InventoryRecord(BaseModel):
    model_config = ConfigDict(frozen=True)


class VirtualMachine(_InventoryRecord):
    vmid: str
    name: str
    status: str

    @property
    def is_running(self) -> bool:
        return self.status.lower() == "running"


class LXCContainer(_InventoryRecord):
    ctid: str
    name: str
    status: str

    @property
    def is_running(self) -> bool:
        return self.status.lower() == "running"


def shlex_join(parts: Sequence[str]) -> str:
    return " ".join(shlex.quote(part) for part in parts)


class Reconciler(Protocol):
    async def reconcile(self) -> None: ...


class NodeRecord(BaseModel):
    node: str

    model_config = ConfigDict(extra="ignore")


class VMRecord(BaseModel):
    vmid: int
    name: str | None = None
    status: str | None = None

    model_config = ConfigDict(extra="ignore")


class ContainerRecord(BaseModel):
    vmid: int
    name: str | None = None
    status: str | None = None

    model_config = ConfigDict(extra="ignore")


class GuestInterfaceAddress(BaseModel):
    ip_address: str = Field(alias="ip-address")
    ip_address_type: str = Field(alias="ip-address-type")

    model_config = ConfigDict(populate_by_name=True)


def _empty_address_list() -> list[GuestInterfaceAddress]:
    return []


class GuestInterface(BaseModel):
    name: str | None = None
    ip_addresses: list[GuestInterfaceAddress] = Field(
        default_factory=_empty_address_list,
        alias="ip-addresses",
    )

    model_config = ConfigDict(populate_by_name=True)


VM_LIST_ADAPTER = TypeAdapter(list[VMRecord])
CONTAINER_LIST_ADAPTER = TypeAdapter(list[ContainerRecord])
INTERFACE_LIST_ADAPTER = TypeAdapter(list[GuestInterface])
NODE_LIST_ADAPTER = TypeAdapter(list[NodeRecord])


class ProxmoxCLIError(RuntimeError):
    """Raised when inventory commands executed via SSH fail."""


class ProxmoxCLIClient:
    """Inventory helper that shells out to Proxmox CLI tools over SSH."""

    def __init__(self, session: SSHSession) -> None:
        self._session = session

    async def list_vms(self) -> list[VirtualMachine]:
        payload = await self._run_json(
            shlex_join(["qm", "list", "--full", "--output-format", "json"]),
            label="VM list",
        )
        data = self._extract_list(payload, label="VM list")
        try:
            records = VM_LIST_ADAPTER.validate_python(data)
        except ValidationError as exc:
            raise ProxmoxCLIError(f"Invalid VM payload: {exc}") from exc
        return [
            VirtualMachine(
                vmid=str(record.vmid),
                name=record.name or str(record.vmid),
                status=(record.status or "unknown"),
            )
            for record in records
        ]

    async def list_containers(self) -> list[LXCContainer]:
        payload = await self._run_json(
            shlex_join(["pct", "list", "--output-format", "json"]),
            label="Container list",
        )
        data = self._extract_list(payload, label="Container list")
        try:
            records = CONTAINER_LIST_ADAPTER.validate_python(data)
        except ValidationError as exc:
            raise ProxmoxCLIError(f"Invalid container payload: {exc}") from exc
        return [
            LXCContainer(
                ctid=str(record.vmid),
                name=record.name or str(record.vmid),
                status=(record.status or "unknown"),
            )
            for record in records
        ]

    async def fetch_vm_interfaces(self, vmid: str) -> list[GuestInterface]:
        payload = await self._run_json(
            shlex_join(["qm", "agent", vmid, "network-get-interfaces"]),
            label=f"VM {vmid} guest interfaces",
        )
        records = self._extract_agent_payload(payload)
        try:
            return INTERFACE_LIST_ADAPTER.validate_python(records)
        except ValidationError as exc:
            raise ProxmoxCLIError(f"Invalid interface payload: {exc}") from exc

    async def _run_json(self, command: str, *, label: str) -> Any:
        try:
            result = await self._session.run(command, capture_output=True, mutable=False)
        except CommandExecutionError as exc:
            raise ProxmoxCLIError(f"{label} command failed: {exc}") from exc
        text = result.stdout.strip()
        if not text:
            raise ProxmoxCLIError(f"{label} returned no data")
        try:
            return json.loads(text)
        except json.JSONDecodeError as exc:
            raise ProxmoxCLIError(f"{label} returned invalid JSON: {exc}") from exc

    def _extract_list(self, payload: Any, *, label: str) -> list[Any]:
        if isinstance(payload, list):
            return cast(list[Any], payload)
        if isinstance(payload, Mapping):
            mapping = cast(Mapping[str, Any], payload)
            data = mapping.get("data")
            if isinstance(data, list):
                return cast(list[Any], data)
        raise ProxmoxCLIError(f"{label} output could not be parsed as a list")

    def _extract_agent_payload(self, payload: Any) -> Any:
        if isinstance(payload, Mapping):
            mapping = cast(Mapping[str, Any], payload)
            if "result" in mapping:
                return mapping["result"]
            if "data" in mapping:
                return mapping["data"]
            return cast(Any, mapping)
        return payload


class VirtualMachineAgent:
    def __init__(
        self,
        vm: VirtualMachine,
        proxmox_session: SSHSession,
        inventory_client: ProxmoxCLIClient,
        guest_options: GuestSSHOptions,
    ) -> None:
        self.vm = vm
        self.proxmox_session = proxmox_session
        self.inventory_client = inventory_client
        self.guest_options = guest_options

    async def reconcile(self) -> None:
        logger.info("process-vm", name=self.vm.name, vmid=self.vm.vmid)
        was_running = self.vm.is_running
        if self.vm.is_running:
            await self.stop_vm()
        await self.backup_vm()
        await self.start_vm()
        ip_address = await self.fetch_ip()
        if ip_address:
            await attempt_guest_upgrade(
                ip_address=ip_address,
                default_user=self.guest_options.user,
                options=self.guest_options,
                dry_run=self.proxmox_session.dry_run,
                identifier=f"vm-{self.vm.vmid}",
            )
        else:
            logger.warning("vm-ip-missing", vmid=self.vm.vmid)
        if not was_running:
            await self.stop_vm()

    async def stop_vm(self) -> None:
        logger.info("stop-vm", vmid=self.vm.vmid)
        cmd = shlex_join(["qm", "shutdown", self.vm.vmid, "--timeout", "120"])
        await self.proxmox_session.run(cmd, capture_output=False, mutable=True)
        self.vm.status = "stopped"

    async def backup_vm(self) -> None:
        logger.info("backup-vm", vmid=self.vm.vmid)
        cmd = shlex_join(["vzdump", self.vm.vmid, "--mode", "snapshot", "--compress", "zstd"])
        await self.proxmox_session.run(cmd, capture_output=False, mutable=True)

    async def start_vm(self) -> None:
        logger.info("start-vm", vmid=self.vm.vmid)
        cmd = shlex_join(["qm", "start", self.vm.vmid])
        await self.proxmox_session.run(cmd, capture_output=False, mutable=True)
        self.vm.status = "running"

    async def fetch_ip(self) -> str | None:
        try:
            interfaces = await self.inventory_client.fetch_vm_interfaces(self.vm.vmid)
        except ProxmoxCLIError as exc:
            logger.error("vm-ip-fetch-error", vmid=self.vm.vmid, error=str(exc))
            return None
        for iface in interfaces:
            for address in iface.ip_addresses:
                if address.ip_address_type.lower() == "ipv4":
                    return address.ip_address
        return None


class ContainerAgent:
    def __init__(
        self,
        container: LXCContainer,
        proxmox_session: SSHSession,
        guest_options: GuestSSHOptions,
    ) -> None:
        self.container = container
        self.proxmox_session = proxmox_session
        self.guest_options = guest_options

    async def reconcile(self) -> None:
        logger.info("process-ct", name=self.container.name, ctid=self.container.ctid)
        was_running = self.container.is_running
        if self.container.is_running:
            await self.stop()
        await self.backup()
        await self.start()
        ip_address = await self.fetch_ip()
        if ip_address:
            await attempt_guest_upgrade(
                ip_address=ip_address,
                default_user=self.guest_options.user,
                options=self.guest_options,
                dry_run=self.proxmox_session.dry_run,
                identifier=f"ct-{self.container.ctid}",
            )
        else:
            logger.warning("ct-ip-missing", ctid=self.container.ctid)
        if not was_running:
            await self.stop()

    async def stop(self) -> None:
        cmd = shlex_join(["pct", "shutdown", self.container.ctid, "--timeout", "120"])
        await self.proxmox_session.run(cmd, capture_output=False, mutable=True)
        self.container.status = "stopped"

    async def backup(self) -> None:
        cmd = shlex_join(["vzdump", self.container.ctid, "--mode", "snapshot", "--compress", "zstd"])
        await self.proxmox_session.run(cmd, capture_output=False, mutable=True)

    async def start(self) -> None:
        cmd = shlex_join(["pct", "start", self.container.ctid])
        await self.proxmox_session.run(cmd, capture_output=False, mutable=True)
        self.container.status = "running"

    async def fetch_ip(self) -> str | None:
        cmd = shlex_join(["pct", "exec", self.container.ctid, "--", "hostname", "-I"])
        try:
            result = await self.proxmox_session.run(cmd, capture_output=True, mutable=False)
        except CommandExecutionError as exc:
            logger.error("ct-ip-fetch-error", ctid=self.container.ctid, error=str(exc))
            return None
        for token in result.stdout.split():
            if is_ipv4_address(token):
                return token
        return None


def is_ipv4_address(value: str) -> bool:
    parts = value.split(".")
    if len(parts) != 4:
        return False
    try:
        return all(0 <= int(part) <= 255 for part in parts)
    except ValueError:
        return False


class ProxmoxAgent:
    def __init__(
        self,
        proxmox_session: SSHSession,
        inventory_client: ProxmoxCLIClient,
        guest_options: GuestSSHOptions,
        max_parallel: int,
    ) -> None:
        self.proxmox_session = proxmox_session
        self.inventory_client = inventory_client
        self.guest_options = guest_options
        self.max_parallel = max(1, max_parallel)

    async def run(self) -> None:
        try:
            vms = await self.inventory_client.list_vms()
        except ProxmoxCLIError as exc:
            logger.error("vm-list-error", error=str(exc))
            vms = []
        await self._run_with_limit(
            [
                VirtualMachineAgent(
                    vm,
                    self.proxmox_session,
                    self.inventory_client,
                    self.guest_options,
                )
                for vm in vms
            ]
        )
        try:
            containers = await self.inventory_client.list_containers()
        except ProxmoxCLIError as exc:
            logger.error("container-list-error", error=str(exc))
            containers = []
        await self._run_with_limit(
            [ContainerAgent(ct, self.proxmox_session, self.guest_options) for ct in containers]
        )
        await self.upgrade_proxmox_host()

    async def _run_with_limit(self, agents: Sequence[Reconciler]) -> None:
        if not agents:
            return
        semaphore = asyncio.Semaphore(self.max_parallel)

        async def worker(agent: Reconciler) -> None:
            async with semaphore:
                await agent.reconcile()

        await asyncio.gather(*(worker(agent) for agent in agents))

    async def upgrade_proxmox_host(self) -> None:
        logger.info("host-upgrade")
        try:
            release_content = await self.proxmox_session.run(
                "cat /etc/os-release", capture_output=True, mutable=False
            )
        except CommandExecutionError as exc:
            logger.error("host-os-release-error", error=str(exc))
            return
        os_release = parse_os_release(release_content.stdout)
        package_manager = determine_package_manager(os_release)
        if not package_manager:
            logger.error("host-upgrade-unsupported")
            return
        command = build_upgrade_command(package_manager, use_sudo=False)
        try:
            await self.proxmox_session.run(command, capture_output=False, mutable=True)
        except CommandExecutionError as exc:
            logger.error("host-upgrade-failed", error=str(exc))


def ensure_valid_host_argument(host: str) -> str:
    trimmed = (host or "").strip()
    if not trimmed:
        raise ValueError("Host/IP address is required (example: proxmox.example.com)")
    if trimmed.startswith("-"):
        raise ValueError(
            "Host parameter appears missing. Provide the Proxmox host before options, e.g. "
            "`proxmox_maintenance proxmox.example --dry-run`. "
            "To show help, run without the extra `--` (example: `proxmox_maintenance --help`)."
        )
    return trimmed


async def run_with_options(options: MaintenanceRunOptions) -> int:
    host_session = SSHSession(
        host=options.host,
        user=options.user,
        dry_run=options.dry_run,
        identity_file=str(options.identity_file) if options.identity_file else None,
        extra_args=options.ssh_extra_args,
        description="proxmox",
    )
    guest_options = GuestSSHOptions(
        user=options.guest_user,
        identity_file=str(options.guest_identity_file) if options.guest_identity_file else None,
        extra_args=options.guest_ssh_extra_args,
    )
    inventory_client = ProxmoxCLIClient(host_session)
    agent = ProxmoxAgent(host_session, inventory_client, guest_options, max_parallel=options.max_parallel)
    await agent.run()
    return 0


def _host_argument(value: str) -> str:
    try:
        return ensure_valid_host_argument(value)
    except ValueError as exc:
        raise typer.BadParameter(str(exc)) from exc


_HOST_ARGUMENT = typer.Argument(
    ...,
    help="Proxmox host IPv4/IPv6 or DNS",
    callback=_host_argument,
)
_USER_OPTION = typer.Option("root", "--user", "-u", help="Proxmox SSH user")
_IDENTITY_FILE_OPTION = typer.Option(
    None,
    "--identity-file",
    help="SSH identity for Proxmox host",
)
_GUEST_USER_OPTION = typer.Option("root", "--guest-user", help="Guest SSH user")
_GUEST_IDENTITY_FILE_OPTION = typer.Option(
    None,
    "--guest-identity-file",
    help="Guest SSH identity file",
)
_GUEST_SSH_EXTRA_ARG_OPTION = typer.Option(
    None,
    "--guest-ssh-extra-arg",
    help="Additional ssh arguments for guest connections (repeatable)",
)
_SSH_EXTRA_ARG_OPTION = typer.Option(
    None,
    "--ssh-extra-arg",
    help="Additional ssh arguments for Proxmox host connection (repeatable)",
)
_MAX_PARALLEL_OPTION = typer.Option(
    2,
    "--max-parallel",
    min=1,
    help="Maximum concurrent guest operations",
)
_DRY_RUN_OPTION = typer.Option(False, "--dry-run", help="Log actions without changing state")
_VERBOSE_OPTION = typer.Option(False, "--verbose", "-v", help="Enable debug logging")


@app.command("run", no_args_is_help=True)
def cli_run(
    host: str = _HOST_ARGUMENT,
    user: str = _USER_OPTION,
    identity_file: Path | None = _IDENTITY_FILE_OPTION,
    guest_user: str = _GUEST_USER_OPTION,
    guest_identity_file: Path | None = _GUEST_IDENTITY_FILE_OPTION,
    guest_ssh_extra_arg: list[str] | None = _GUEST_SSH_EXTRA_ARG_OPTION,
    ssh_extra_arg: list[str] | None = _SSH_EXTRA_ARG_OPTION,
    max_parallel: int = _MAX_PARALLEL_OPTION,
    dry_run: bool = _DRY_RUN_OPTION,
    verbose: bool = _VERBOSE_OPTION,
) -> None:
    _print_cli_notice()
    configure_logging(verbose)
    options = MaintenanceRunOptions(
        host=host,
        user=user,
        identity_file=_expand_optional_path(identity_file),
        ssh_extra_args=tuple(ssh_extra_arg or []),
        guest_user=guest_user,
        guest_identity_file=_expand_optional_path(guest_identity_file),
        guest_ssh_extra_args=tuple(guest_ssh_extra_arg or []),
        max_parallel=max_parallel,
        dry_run=dry_run,
    )
    exit_code = asyncio.run(run_with_options(options))
    raise typer.Exit(exit_code)


def main() -> None:
    app()


if __name__ == "__main__":
    main()
