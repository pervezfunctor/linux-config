from __future__ import annotations

from pathlib import Path
from typing import cast

import pytest
from _pytest.monkeypatch import MonkeyPatch

import proxmox_batch


def _make_host(**overrides: object) -> proxmox_batch.HostConfig:
    return proxmox_batch.HostConfig(
        name=cast(str, overrides.get("name", "prod-a")),
        host=cast(str, overrides.get("host", "proxmox-a.example.com")),
        user=cast(str, overrides.get("user", "root")),
        guest_ssh_extra_args=cast(tuple[str, ...], overrides.get("guest_ssh_extra_args", ())),
        max_parallel=cast(int, overrides.get("max_parallel", 2)),
        dry_run=cast(bool, overrides.get("dry_run", False)),
    )


def test_load_manifest_merges_defaults(tmp_path: Path) -> None:
    manifest = tmp_path / "hosts.toml"
    manifest.write_text(
        """
        [defaults]
        user = "root"
        identity_file = "~/.ssh/proxmox"
        ssh.extra_args = ["-J", "bastion"]
        guest.user = "root"
        guest.identity_file = "~/.ssh/guest-default"
        dry_run = false

        [[hosts]]
        name = "prod-a"
        host = "proxmox-a.example.com"

        [[hosts]]
        host = "proxmox-b.example.com"
        user = "admin"
        guest.user = "ops"
        ssh.extra_args = ["-o", "ProxyJump=jumper"]
        dry_run = true
        """
    )

    defaults, hosts = proxmox_batch.load_manifest(manifest)

    assert defaults.user == "root"
    assert len(hosts) == 2

    host_a, host_b = hosts
    assert host_a.name == "prod-a"
    assert host_a.user == "root"

    assert host_b.name == "proxmox-b.example.com"
    assert host_b.user == "admin"
    assert host_b.dry_run is True

    assert defaults.identity_file is not None
    options = proxmox_batch.build_host_options(host_b, defaults, force_dry_run=False)
    assert options.identity_file == Path(defaults.identity_file)
    assert options.guest_user == defaults.guest_user
    assert options.ssh_extra_args == defaults.ssh_extra_args


def test_host_filtering() -> None:
    host_a = _make_host(name="a", host="a.local")
    host_b = _make_host(name="b", host="b.local")
    selected = proxmox_batch.select_hosts([host_a, host_b], ["b"])
    assert selected == [host_b]
    with pytest.raises(ValueError):
        proxmox_batch.select_hosts([host_a, host_b], ["unknown"])


def test_build_host_options_reflects_manifest_values() -> None:
    host = _make_host(
        guest_ssh_extra_args=("-o StrictHostKeyChecking=no",),
        max_parallel=4,
        dry_run=True,
    )

    defaults = proxmox_batch.BatchDefaults(
        identity_file=str(Path("~/.ssh/proxmox").expanduser()),
        ssh_extra_args=("-J bastion",),
        guest_identity_file=str(Path("~/.ssh/guest").expanduser()),
        guest_user="ops",
    )

    assert defaults.identity_file is not None
    options = proxmox_batch.build_host_options(host, defaults, force_dry_run=False)
    assert options.host == host.host
    assert options.identity_file == Path(defaults.identity_file)
    assert options.ssh_extra_args == defaults.ssh_extra_args
    assert options.guest_ssh_extra_args == host.guest_ssh_extra_args
    assert options.guest_user == defaults.guest_user
    assert options.max_parallel == host.max_parallel
    assert options.dry_run is True

    forced = proxmox_batch.build_host_options(host, defaults, force_dry_run=True)
    assert forced.dry_run is True


@pytest.mark.asyncio
async def test_async_run_batch_handles_mixed_results(monkeypatch: MonkeyPatch, tmp_path: Path) -> None:
    host_success = _make_host(name="success")
    host_failure = _make_host(name="failure")

    async def fake_run_host(
        host: proxmox_batch.HostConfig,
        defaults: proxmox_batch.BatchDefaults,
        *,
        force_dry_run: bool,
    ) -> tuple[bool, str | None]:
        return (host.name == "success", None if host.name == "success" else "boom")

    monkeypatch.setattr(proxmox_batch, "run_host", fake_run_host)

    def fake_load_manifest(_path: Path) -> tuple[proxmox_batch.BatchDefaults, list[proxmox_batch.HostConfig]]:
        return proxmox_batch.BatchDefaults(), [host_success, host_failure]

    monkeypatch.setattr(proxmox_batch, "load_manifest", fake_load_manifest)

    exit_code = await proxmox_batch.async_run_batch(
        config_path=tmp_path / "dummy.toml",
        host_filters=(),
        limit=None,
        force_dry_run=False,
        verbose=False,
    )
    assert exit_code == 3
