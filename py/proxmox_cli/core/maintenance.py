"""Core maintenance logic for Proxmox hosts and guests."""

from __future__ import annotations

import asyncio
import json
import shlex
from collections.abc import Mapping, Sequence
from typing import Any, Protocol, cast

import structlog
from pydantic import BaseModel, ConfigDict, Field, TypeAdapter, ValidationError

from proxmox_cli.core.exceptions import ProxmoxCLIError
from proxmox_cli.core.models import MaintenanceRunOptions
from proxmox_cli.utils import CommandExecutionError, GuestSSHOptions, SSHSession, attempt_guest_upgrade

logger = structlog.get_logger(__name__)


def shlex_join(parts: Sequence[str]) -> str:
    return " ".join(shlex.quote(part) for part in parts)


class Reconciler(Protocol):
    async def reconcile(self) -> None: ...


# Inventory Models


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


# Proxmox CLI Client


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


# Agent Classes


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
        from proxmox_cli.utils.ssh import (
            build_upgrade_command,
            determine_package_manager,
            parse_os_release,
        )

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


async def run_with_options(options: MaintenanceRunOptions) -> int:
    """Run maintenance with the given options."""
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


__all__ = [
    "ContainerAgent",
    "LXCContainer",
    "ProxmoxAgent",
    "ProxmoxCLIClient",
    "VirtualMachine",
    "VirtualMachineAgent",
    "run_with_options",
]
