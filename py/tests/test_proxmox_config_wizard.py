import tomllib
from pathlib import Path

import pytest

from proxmox_batch import ManifestError
from proxmox_manifest import load_manifest_state, validate_state, write_manifest
from proxmox_manifest_models import DefaultsForm, HostForm, ManifestState

SAMPLE_MANIFEST = """
title = "primary cluster"

[defaults]
user = "root"
guest_user = "admin"
identity_file = "~/.ssh/proxmox"
ssh_extra_args = ["-J", "bastion"]
[defaults.custom]
notes = "keep me"

[[hosts]]
name = "alpha"
host = "alpha.example.com"
ssh_extra_args = ["-o", "StrictHostKeyChecking=no"]
metadata = { role = "db" }

[[hosts]]
host = "beta.example.com"
"""


def _write_sample(path: Path) -> Path:
    path.write_text(SAMPLE_MANIFEST, encoding="utf-8")
    return path


def test_load_manifest_state_preserves_extras(tmp_path: Path) -> None:
    manifest_path = _write_sample(tmp_path / "proxmox-hosts.toml")
    state = load_manifest_state(manifest_path)

    assert state.top_level_extras["title"] == "primary cluster"
    assert state.defaults.user == "root"
    assert state.defaults.extras["custom"]["notes"] == "keep me"
    assert state.defaults.ssh_extra_args == ["-J", "bastion"]

    assert len(state.hosts) == 2
    alpha = state.hosts[0]
    assert alpha.name == "alpha"
    assert "ssh_extra_args" not in alpha.extras
    assert alpha.extras["metadata"]["role"] == "db"

    beta = state.hosts[1]
    assert beta.name == "beta.example.com"
    assert beta.host == "beta.example.com"


def test_write_manifest_round_trip(tmp_path: Path) -> None:
    manifest_path = _write_sample(tmp_path / "proxmox-hosts.toml")
    state = load_manifest_state(manifest_path)

    state.defaults.user = "admin"
    state.defaults.max_parallel = 4
    state.hosts[0].guest_ssh_extra_args = ["-o", "StrictHostKeyChecking=no"]
    state.hosts[0].dry_run = True

    output_path = tmp_path / "out.toml"
    write_manifest(state, output_path)

    data = tomllib.loads(output_path.read_text(encoding="utf-8"))
    assert data["title"] == "primary cluster"
    assert data["defaults"]["user"] == "admin"
    assert data["defaults"]["max_parallel"] == 4
    assert len(data["hosts"]) == 2
    assert "ssh_extra_args" not in data["hosts"][0]
    assert data["hosts"][0]["guest_ssh_extra_args"] == ["-o", "StrictHostKeyChecking=no"]
    assert data["hosts"][0]["dry_run"] is True
    assert data["hosts"][0]["metadata"]["role"] == "db"


def test_validate_state_rejects_duplicate_names() -> None:
    defaults = DefaultsForm()
    host_a = HostForm(
        name="alpha",
        host="alpha.example.com",
    )
    host_b = HostForm(
        name="alpha",
        host="alpha2.example.com",
    )
    state = ManifestState(defaults=defaults, hosts=[host_a, host_b])

    with pytest.raises(ManifestError):
        validate_state(state)
