"""Unit tests for proxmox_inventory_builder.py."""

from __future__ import annotations

from datetime import UTC, datetime
from pathlib import Path
from unittest.mock import patch

import pytest

from proxmox_inventory_builder import (
    GuestDiscovery,
    InventoryError,
    InventoryRunOptions,
    ManagedGuest,
    expand_optional_path,
    load_existing_guest_map,
    load_manifest,
    run_inventory,
    save_manifest,
    update_host_inventory,
)
from proxmox_manifest_models import DefaultsForm, HostForm, ManifestState
from questionary_prompts import WizardAbort

SAMPLE_MANIFEST = """
title = "test cluster"

[defaults]
user = "root"
guest_user = "admin"
identity_file = "~/.ssh/proxmox"

[[hosts]]
name = "alpha"
host = "alpha.example.com"

[[hosts]]
name = "beta"
host = "beta.example.com"
"""


def _write_sample(path: Path) -> Path:
    path.write_text(SAMPLE_MANIFEST, encoding="utf-8")
    return path


class TestInventoryRunOptions:
    """Tests for InventoryRunOptions dataclass."""

    def test_inventory_run_options_defaults(self) -> None:
        """Test InventoryRunOptions with default values."""
        manifest_path = Path("/tmp/manifest.toml")
        options = InventoryRunOptions(manifest=manifest_path)

        assert options.manifest == manifest_path
        assert options.host is None
        assert options.verbose is False

    def test_inventory_run_options_with_values(self) -> None:
        """Test InventoryRunOptions with all values set."""
        manifest_path = Path("/tmp/manifest.toml")
        options = InventoryRunOptions(manifest=manifest_path, host="alpha", verbose=True)

        assert options.manifest == manifest_path
        assert options.host == "alpha"
        assert options.verbose is True


class TestGuestDiscovery:
    """Tests for GuestDiscovery model."""

    def test_guest_discovery_vm(self) -> None:
        """Test GuestDiscovery for a VM."""
        discovery = GuestDiscovery(
            kind="vm",
            identifier="100",
            name="test-vm",
            status="running",
            ip="192.168.1.100",
        )

        assert discovery.kind == "vm"
        assert discovery.identifier == "100"
        assert discovery.name == "test-vm"
        assert discovery.status == "running"
        assert discovery.ip == "192.168.1.100"
        assert discovery.label == "VM test-vm (100)"

    def test_guest_discovery_ct(self) -> None:
        """Test GuestDiscovery for a container."""
        discovery = GuestDiscovery(
            kind="ct",
            identifier="101",
            name="test-ct",
            status="running",
            ip="192.168.1.101",
        )

        assert discovery.kind == "ct"
        assert discovery.identifier == "101"
        assert discovery.name == "test-ct"
        assert discovery.status == "running"
        assert discovery.ip == "192.168.1.101"
        assert discovery.label == "CT test-ct (101)"

    def test_guest_discovery_without_ip(self) -> None:
        """Test GuestDiscovery without IP address."""
        discovery = GuestDiscovery(kind="vm", identifier="100", name="test-vm", status="stopped", ip=None)

        assert discovery.ip is None
        assert discovery.label == "VM test-vm (100)"


class TestManagedGuest:
    """Tests for ManagedGuest model."""

    def test_managed_guest_with_notes(self) -> None:
        """Test ManagedGuest with notes."""
        discovery = GuestDiscovery(
            kind="vm",
            identifier="100",
            name="test-vm",
            status="running",
            ip="192.168.1.100",
        )
        last_checked = datetime.now(UTC).isoformat()
        guest = ManagedGuest(
            discovery=discovery,
            managed=True,
            notes="Production database",
            last_checked=last_checked,
        )

        assert guest.managed is True
        assert guest.notes == "Production database"
        assert guest.last_checked == last_checked

    def test_managed_guest_without_notes(self) -> None:
        """Test ManagedGuest without notes."""
        discovery = GuestDiscovery(
            kind="vm",
            identifier="100",
            name="test-vm",
            status="running",
            ip="192.168.1.100",
        )
        last_checked = datetime.now(UTC).isoformat()
        guest = ManagedGuest(discovery=discovery, managed=False, notes=None, last_checked=last_checked)

        assert guest.managed is False
        assert guest.notes is None

    def test_managed_guest_to_dict_with_notes(self) -> None:
        """Test ManagedGuest.to_dict() with notes."""
        discovery = GuestDiscovery(
            kind="vm",
            identifier="100",
            name="test-vm",
            status="running",
            ip="192.168.1.100",
        )
        last_checked = datetime.now(UTC).isoformat()
        guest = ManagedGuest(
            discovery=discovery,
            managed=True,
            notes="Important notes",
            last_checked=last_checked,
        )

        result = guest.to_dict()

        assert result["kind"] == "vm"
        assert result["id"] == "100"
        assert result["name"] == "test-vm"
        assert result["status"] == "running"
        assert result["ip"] == "192.168.1.100"
        assert result["managed"] is True
        assert result["last_checked"] == last_checked
        assert result["notes"] == "Important notes"

    def test_managed_guest_to_dict_without_notes(self) -> None:
        """Test ManagedGuest.to_dict() without notes."""
        discovery = GuestDiscovery(
            kind="ct",
            identifier="101",
            name="test-ct",
            status="running",
            ip="192.168.1.101",
        )
        last_checked = datetime.now(UTC).isoformat()
        guest = ManagedGuest(discovery=discovery, managed=False, notes=None, last_checked=last_checked)

        result = guest.to_dict()

        assert result["kind"] == "ct"
        assert result["id"] == "101"
        assert result["name"] == "test-ct"
        assert result["status"] == "running"
        assert result["ip"] == "192.168.1.101"
        assert result["managed"] is False
        assert result["last_checked"] == last_checked
        assert "notes" not in result


class TestInventoryError:
    """Tests for InventoryError exception."""

    def test_inventory_error_message(self) -> None:
        """Test InventoryError with a message."""
        error = InventoryError("Test error message")

        assert str(error) == "Test error message"
        assert isinstance(error, RuntimeError)


class TestExpandOptionalPath:
    """Tests for expand_optional_path function."""

    def test_expand_optional_path_none(self) -> None:
        """Test expand_optional_path with None."""
        result = expand_optional_path(None)

        assert result is None

    def test_expand_optional_path_empty_string(self) -> None:
        """Test expand_optional_path with empty string."""
        result = expand_optional_path("")

        assert result is None

    def test_expand_optional_path_with_tilde(self, monkeypatch: pytest.MonkeyPatch) -> None:
        """Test expand_optional_path with tilde."""
        fake_home = Path("/tmp/fake_home")
        monkeypatch.setenv("HOME", str(fake_home))

        result = expand_optional_path("~/test/path")

        assert result == str(fake_home / "test/path")

    def test_expand_optional_path_without_tilde(self) -> None:
        """Test expand_optional_path without tilde."""
        result = expand_optional_path("/absolute/path")

        assert result == "/absolute/path"

    def test_expand_optional_path_relative(self) -> None:
        """Test expand_optional_path with relative path."""
        result = expand_optional_path("relative/path")

        assert result == str(Path("relative/path").expanduser())


class TestExtractIPv4:
    """Tests for _extract_ipv4 function."""

    def test_extract_ipv4_valid(self) -> None:
        """Test _extract_ipv4 with valid IPv4 address."""
        from proxmox_inventory_builder import extract_ipv4

        result = extract_ipv4("192.168.1.100")

        assert result == "192.168.1.100"

    def test_extract_ipv4_multiple_addresses(self) -> None:
        """Test _extract_ipv4 with multiple addresses."""
        from proxmox_inventory_builder import extract_ipv4

        result = extract_ipv4("192.168.1.100 10.0.0.1 172.16.0.1")

        assert result == "192.168.1.100"

    def test_extract_ipv4_with_invalid_addresses(self) -> None:
        """Test _extract_ipv4 with invalid addresses mixed in."""
        from proxmox_inventory_builder import extract_ipv4

        result = extract_ipv4("invalid 192.168.1.100 300.400.500.600")

        assert result == "192.168.1.100"

    def test_extract_ipv4_no_valid_address(self) -> None:
        """Test _extract_ipv4 with no valid IPv4 address."""
        from proxmox_inventory_builder import extract_ipv4

        result = extract_ipv4("invalid 300.400.500.600")

        assert result is None

    def test_extract_ipv4_empty_string(self) -> None:
        """Test _extract_ipv4 with empty string."""
        from proxmox_inventory_builder import extract_ipv4

        result = extract_ipv4("")

        assert result is None

    def test_extract_ipv4_ipv6_address(self) -> None:
        """Test _extract_ipv4 with IPv6 address."""
        from proxmox_inventory_builder import extract_ipv4

        result = extract_ipv4("2001:db8::1")

        assert result is None

    def test_extract_ipv4_boundary_values(self) -> None:
        """Test _extract_ipv4 with boundary IP values."""
        from proxmox_inventory_builder import extract_ipv4

        assert extract_ipv4("0.0.0.0") == "0.0.0.0"
        assert extract_ipv4("255.255.255.255") == "255.255.255.255"


class TestLoadExistingGuestMap:
    """Tests for load_existing_guest_map function."""

    def test_load_existing_guest_map_no_extras(self) -> None:
        """Test load_existing_guest_map with no extras."""
        host = HostForm(name="test", host="test.example.com")

        result = load_existing_guest_map(host)

        assert result == {}

    def test_load_existing_guest_map_empty_extras(self) -> None:
        """Test load_existing_guest_map with empty extras."""
        host = HostForm(name="test", host="test.example.com", extras={})

        result = load_existing_guest_map(host)

        assert result == {}

    def test_load_existing_guest_map_no_guest_inventory_key(self) -> None:
        """Test load_existing_guest_map without guest_inventory key."""
        host = HostForm(name="test", host="test.example.com", extras={"other_key": "value"})

        result = load_existing_guest_map(host)

        assert result == {}

    def test_load_existing_guest_map_no_entries(self) -> None:
        """Test load_existing_guest_map without entries."""
        host = HostForm(
            name="test",
            host="test.example.com",
            extras={"guest_inventory": {"version": 1}},
        )

        result = load_existing_guest_map(host)

        assert result == {}

    def test_load_existing_guest_map_empty_entries(self) -> None:
        """Test load_existing_guest_map with empty entries."""
        host = HostForm(
            name="test",
            host="test.example.com",
            extras={"guest_inventory": {"version": 1, "entries": []}},
        )

        result = load_existing_guest_map(host)

        assert result == {}

    def test_load_existing_guest_map_with_entries(self) -> None:
        """Test load_existing_guest_map with valid entries."""
        host = HostForm(
            name="test",
            host="test.example.com",
            extras={
                "guest_inventory": {
                    "version": 1,
                    "entries": [
                        {
                            "kind": "vm",
                            "id": "100",
                            "name": "test-vm",
                            "status": "running",
                            "ip": "192.168.1.100",
                            "managed": True,
                            "last_checked": "2024-01-01T00:00:00+00:00",
                            "notes": "Test notes",
                        },
                        {
                            "kind": "ct",
                            "id": "101",
                            "name": "test-ct",
                            "status": "stopped",
                            "ip": "192.168.1.101",
                            "managed": False,
                            "last_checked": "2024-01-01T00:00:00+00:00",
                        },
                    ],
                }
            },
        )

        result = load_existing_guest_map(host)

        assert len(result) == 2
        assert ("vm", "100") in result
        assert ("ct", "101") in result
        assert result[("vm", "100")]["managed"] is True
        assert result[("vm", "100")]["notes"] == "Test notes"
        assert result[("ct", "101")]["managed"] is False

    def test_load_existing_guest_map_invalid_entries(self) -> None:
        """Test load_existing_guest_map with invalid entries."""
        host = HostForm(
            name="test",
            host="test.example.com",
            extras={
                "guest_inventory": {
                    "version": 1,
                    "entries": [
                        {"kind": "vm", "id": "100"},  # Valid
                        {"name": "test"},  # Missing kind and id
                        None,  # None entry
                        "invalid",  # String entry
                    ],
                }
            },
        )

        result = load_existing_guest_map(host)

        assert len(result) == 1
        assert ("vm", "100") in result


class TestUpdateHostInventory:
    """Tests for update_host_inventory function."""

    def test_update_host_inventory_creates_new_inventory(self) -> None:
        """Test update_host_inventory creates new inventory."""
        host = HostForm(name="test", host="test.example.com", extras={})

        discovery = GuestDiscovery(
            kind="vm",
            identifier="100",
            name="test-vm",
            status="running",
            ip="192.168.1.100",
        )
        guest = ManagedGuest(
            discovery=discovery, managed=True, notes="Test", last_checked="2024-01-01T00:00:00+00:00"
        )

        update_host_inventory(host, [guest])

        assert "guest_inventory" in host.extras
        assert host.extras["guest_inventory"]["version"] == 1
        assert "updated_at" in host.extras["guest_inventory"]
        assert len(host.extras["guest_inventory"]["entries"]) == 1
        assert host.extras["guest_inventory"]["entries"][0]["id"] == "100"

    def test_update_host_inventory_overwrites_existing(self) -> None:
        """Test update_host_inventory overwrites existing inventory."""
        host = HostForm(
            name="test",
            host="test.example.com",
            extras={
                "guest_inventory": {
                    "version": 1,
                    "updated_at": "old-date",
                    "entries": [{"kind": "vm", "id": "99"}],
                }
            },
        )

        discovery = GuestDiscovery(
            kind="vm",
            identifier="100",
            name="test-vm",
            status="running",
            ip="192.168.1.100",
        )
        guest = ManagedGuest(
            discovery=discovery, managed=True, notes=None, last_checked="2024-01-01T00:00:00+00:00"
        )

        update_host_inventory(host, [guest])

        assert host.extras["guest_inventory"]["version"] == 1
        assert host.extras["guest_inventory"]["updated_at"] != "old-date"
        assert len(host.extras["guest_inventory"]["entries"]) == 1
        assert host.extras["guest_inventory"]["entries"][0]["id"] == "100"

    def test_update_host_inventory_multiple_guests(self) -> None:
        """Test update_host_inventory with multiple guests."""
        host = HostForm(name="test", host="test.example.com", extras={})

        discovery1 = GuestDiscovery(
            kind="vm",
            identifier="100",
            name="test-vm",
            status="running",
            ip="192.168.1.100",
        )
        discovery2 = GuestDiscovery(
            kind="ct",
            identifier="101",
            name="test-ct",
            status="stopped",
            ip="192.168.1.101",
        )
        guest1 = ManagedGuest(
            discovery=discovery1, managed=True, notes=None, last_checked="2024-01-01T00:00:00+00:00"
        )
        guest2 = ManagedGuest(
            discovery=discovery2, managed=False, notes="Test", last_checked="2024-01-01T00:00:00+00:00"
        )

        update_host_inventory(host, [guest1, guest2])

        assert len(host.extras["guest_inventory"]["entries"]) == 2
        assert host.extras["guest_inventory"]["entries"][0]["id"] == "100"
        assert host.extras["guest_inventory"]["entries"][1]["id"] == "101"


class TestLoadManifest:
    """Tests for load_manifest function."""

    def test_load_manifest_existing_file(self, tmp_path: Path) -> None:
        """Test load_manifest with existing file."""
        manifest_path = _write_sample(tmp_path / "proxmox-hosts.toml")
        state = load_manifest(manifest_path)

        assert state is not None
        assert len(state.hosts) == 2
        assert state.hosts[0].name == "alpha"

    def test_load_manifest_nonexistent_file(self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
        """Test load_manifest with non-existent file."""
        manifest_path = tmp_path / "nonexistent.toml"

        with patch("proxmox_inventory_builder.questionary.print") as mock_print:
            state = load_manifest(manifest_path)

            assert state is not None
            assert len(state.hosts) == 0
            mock_print.assert_called_once()


class TestSaveManifest:
    """Tests for save_manifest function."""

    def test_save_manifest(self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
        """Test save_manifest."""
        host = HostForm(name="test", host="test.example.com")
        state = ManifestState(defaults=DefaultsForm(), hosts=[host])
        manifest_path = tmp_path / "test.toml"

        with patch("proxmox_inventory_builder.questionary.print") as mock_print:
            save_manifest(state, manifest_path)

            assert manifest_path.exists()
            mock_print.assert_called_once()


class TestRunInventory:
    """Tests for run_inventory function."""

    def test_run_inventory_wizard_abort(self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
        """Test run_inventory with WizardAbort."""
        manifest_path = tmp_path / "test.toml"
        options = InventoryRunOptions(manifest=manifest_path)

        with (
            patch("proxmox_inventory_builder.select_host", side_effect=WizardAbort()),
            patch("proxmox_inventory_builder.questionary.print") as mock_print,
        ):
            result = run_inventory(options)

            assert result == 1
            # Called twice: once for "Creating new manifest", once for "Aborted by user"
            assert mock_print.call_count == 2
            # Verify the abort message was printed
            abort_call = mock_print.call_args_list[-1]
            assert "Aborted by user" in str(abort_call)

    def test_run_inventory_manifest_error(self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
        """Test run_inventory with InventoryError."""
        manifest_path = tmp_path / "test.toml"
        options = InventoryRunOptions(manifest=manifest_path)

        with (
            patch("proxmox_inventory_builder.load_manifest", side_effect=InventoryError("Test error")),
            patch("proxmox_inventory_builder.questionary.print") as mock_print,
        ):
            result = run_inventory(options)

            assert result == 2
            mock_print.assert_called_once()
            # Verify the error message was printed
            error_call = mock_print.call_args_list[0]
            assert "Error:" in str(error_call)

    def test_run_inventory_no_guests_discovered(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """Test run_inventory with no guests discovered."""
        manifest_path = tmp_path / "test.toml"
        options = InventoryRunOptions(manifest=manifest_path)

        state = ManifestState(defaults=DefaultsForm(), hosts=[])
        host = HostForm(name="test", host="test.example.com", user="root")

        with (
            patch("proxmox_inventory_builder.load_manifest", return_value=state),
            patch("proxmox_inventory_builder.select_host", return_value=(host, True)),
            patch("proxmox_inventory_builder.discover_inventory", return_value=[]),
            patch("proxmox_inventory_builder.questionary.print"),
            patch("proxmox_inventory_builder.save_manifest"),
        ):
            result = run_inventory(options)

            # Should succeed even with no guests
            assert result == 0
