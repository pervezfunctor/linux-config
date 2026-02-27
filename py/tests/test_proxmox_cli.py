from __future__ import annotations

import sys
from pathlib import Path
from typing import cast

import pytest
from _pytest.monkeypatch import MonkeyPatch
from pydantic import ValidationError
from typer.testing import CliRunner

from proxmox_cli.app import app
from proxmox_cli.models import BatchOptions
from proxmox_inventory_builder import InventoryRunOptions
from proxmox_maintenance import MaintenanceRunOptions

cli_module = sys.modules["proxmox_cli.app"]


def test_batch_options_enforces_positive_limit() -> None:
    with pytest.raises(ValidationError):
        BatchOptions(
            manifest=Path("/tmp/test.toml"),
            hosts=(),
            limit=0,  # This should fail validation
            force_dry_run=False,
            verbose=False,
        )


def test_maintenance_options_expand_identity(tmp_path: Path, monkeypatch: MonkeyPatch) -> None:
    fake_home = tmp_path / "home"
    fake_home.mkdir()
    monkeypatch.setenv("HOME", str(fake_home))
    options = MaintenanceRunOptions(
        host="pmx",
        user="root",
        identity_file=Path("~/.ssh/key"),
        ssh_extra_args=(),
        guest_user="root",
        guest_identity_file=None,
        guest_ssh_extra_args=(),
        max_parallel=2,
        dry_run=False,
    )
    assert options.identity_file is not None
    assert str(options.identity_file) == "~/.ssh/key"


def test_cli_batch_run_invokes_async_runner(monkeypatch: MonkeyPatch, tmp_path: Path) -> None:
    runner = CliRunner()
    called: dict[str, object] = {}

    async def fake_async_run_batch(**kwargs: object) -> int:
        called.update(kwargs)
        return 0

    monkeypatch.setattr(cli_module, "async_run_batch", fake_async_run_batch)
    result = runner.invoke(
        app,
        [
            "batch",
            "run",
            "--manifest",
            str(tmp_path / "hosts.toml"),
            "--host",
            "alpha",
            "--limit",
            "1",
        ],
    )
    assert result.exit_code == 0
    assert called["host_filters"] == ("alpha",)
    assert called["limit"] == 1


def test_cli_wizard_run_invokes_helper(monkeypatch: MonkeyPatch, tmp_path: Path) -> None:
    runner = CliRunner()
    invoked: dict[str, object] = {}

    def fake_run_wizard(manifest: Path, *, verbose: bool) -> int:
        invoked["manifest"] = manifest
        invoked["verbose"] = verbose
        return 0

    import proxmox_config_wizard

    monkeypatch.setattr(proxmox_config_wizard, "run_wizard", fake_run_wizard)
    result = runner.invoke(
        app,
        [
            "wizard",
            "run",
            "--manifest",
            str(tmp_path / "hosts.toml"),
            "--verbose",
        ],
    )
    assert result.exit_code == 0
    assert invoked["verbose"] is True


def test_cli_inventory_configure_passes_options(monkeypatch: MonkeyPatch, tmp_path: Path) -> None:
    runner = CliRunner()
    captured: dict[str, object] = {}

    def fake_run_inventory(options: InventoryRunOptions) -> int:
        captured["options"] = options
        return 0

    import proxmox_inventory_builder

    monkeypatch.setattr(proxmox_inventory_builder, "run_inventory", fake_run_inventory)
    result = runner.invoke(
        app,
        [
            "inventory",
            "configure",
            "--manifest",
            str(tmp_path / "hosts.toml"),
            "--host",
            "alpha",
        ],
    )
    assert result.exit_code == 0
    options = cast(InventoryRunOptions, captured["options"])
    assert options.host == "alpha"


def test_cli_maintenance_run_invokes_async(monkeypatch: MonkeyPatch) -> None:
    runner = CliRunner()
    captured: dict[str, object] = {}

    async def fake_run_with_options(options: MaintenanceRunOptions) -> int:
        captured["options"] = options
        return 5

    monkeypatch.setattr(cli_module, "run_with_options", fake_run_with_options)
    result = runner.invoke(
        app,
        [
            "maintenance",
            "run",
            "--host",
            "pmx",
            "--user",
            "admin",
            "--ssh-extra-arg",
            "-J bastion",
            "--guest-ssh-extra-arg",
            "-o StrictHostKeyChecking=no",
            "--max-parallel",
            "4",
            "--dry-run",
        ],
    )
    assert result.exit_code == 5
    options = cast(MaintenanceRunOptions, captured["options"])
    assert options.host == "pmx"
    assert options.max_parallel == 4
    assert options.dry_run is True
