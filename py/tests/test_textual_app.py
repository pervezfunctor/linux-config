"""Unit tests for textual_app.py."""

from __future__ import annotations

from pathlib import Path
from typing import Any
from unittest.mock import patch

import pytest

from proxmox_cli.textual_app import AppResult, InventoryBuilderApp, TextualAbort, run_textual_app
from proxmox_inventory_builder import InventoryRunOptions


class TestAppResult:
    """Tests for AppResult dataclass."""

    def test_app_result_success(self) -> None:
        """Test AppResult with success."""
        result = AppResult(exit_code=0, message="Success")

        assert result.exit_code == 0
        assert result.message == "Success"

    def test_app_result_without_message(self) -> None:
        """Test AppResult without message."""
        result = AppResult(exit_code=1)

        assert result.exit_code == 1
        assert result.message is None

    def test_app_result_error(self) -> None:
        """Test AppResult with error."""
        result = AppResult(exit_code=2, message="Error occurred")

        assert result.exit_code == 2
        assert result.message == "Error occurred"


class TestTextualAbort:
    """Tests for TextualAbort exception."""

    def test_textual_abort_is_runtime_error(self) -> None:
        """Test that TextualAbort is a RuntimeError."""
        exc = TextualAbort("User aborted")

        assert isinstance(exc, RuntimeError)
        assert str(exc) == "User aborted"


class TestInventoryBuilderApp:
    """Tests for InventoryBuilderApp."""

    def test_inventory_builder_app_initialization(self) -> None:
        """Test InventoryBuilderApp initialization."""
        manifest_path = Path("/tmp/test.toml")
        options = InventoryRunOptions(manifest=manifest_path, host=None, verbose=False)
        app = InventoryBuilderApp(options)

        assert app.options == options
        assert app.manifest_path == manifest_path
        assert app.manifest_state is None
        assert app.selected_host is None
        assert app.guest_discoveries == []
        assert app.managed_guests == []
        assert app.is_new_host is False

    def test_inventory_builder_app_with_host_option(self) -> None:
        """Test InventoryBuilderApp with host option."""
        manifest_path = Path("/tmp/test.toml")
        options = InventoryRunOptions(manifest=manifest_path, host="test-host", verbose=False)
        app = InventoryBuilderApp(options)

        assert app.options.host == "test-host"

    def test_inventory_builder_app_verbose(self) -> None:
        """Test InventoryBuilderApp with verbose option."""
        manifest_path = Path("/tmp/test.toml")
        options = InventoryRunOptions(manifest=manifest_path, host=None, verbose=True)
        app = InventoryBuilderApp(options)

        assert app.options.verbose is True

    def test_set_result(self) -> None:
        """Test set_result method."""
        manifest_path = Path("/tmp/test.toml")
        options = InventoryRunOptions(manifest=manifest_path, host=None, verbose=False)
        app = InventoryBuilderApp(options)

        app.set_result(0, "Test message")

        result = app.get_result()
        assert result.exit_code == 0
        assert result.message == "Test message"

    def test_set_result_without_message(self) -> None:
        """Test set_result without message."""
        manifest_path = Path("/tmp/test.toml")
        options = InventoryRunOptions(manifest=manifest_path, host=None, verbose=False)
        app = InventoryBuilderApp(options)

        app.set_result(1)

        result = app.get_result()
        assert result.exit_code == 1
        assert result.message is None

    def test_get_result(self) -> None:
        """Test get_result method."""
        manifest_path = Path("/tmp/test.toml")
        options = InventoryRunOptions(manifest=manifest_path, host=None, verbose=False)
        app = InventoryBuilderApp(options)

        app.set_result(0, "Success")
        result = app.get_result()

        assert result.exit_code == 0
        assert result.message == "Success"

    def test_get_result_no_result_set(self) -> None:
        """Test get_result when no result is set."""
        manifest_path = Path("/tmp/test.toml")
        options = InventoryRunOptions(manifest=manifest_path, host=None, verbose=False)
        app = InventoryBuilderApp(options)

        with pytest.raises(RuntimeError, match="No result set"):
            app.get_result()

    def test_inventory_builder_app_bindings(self) -> None:
        """Test that InventoryBuilderApp has correct bindings."""
        manifest_path = Path("/tmp/test.toml")
        options = InventoryRunOptions(manifest=manifest_path, host=None, verbose=False)
        app = InventoryBuilderApp(options)

        assert hasattr(app, "BINDINGS")
        assert ("q", "quit", "Quit") in app.BINDINGS
        assert ("ctrl+c", "quit", "Quit") in app.BINDINGS

    def test_inventory_builder_app_css(self) -> None:
        """Test that InventoryBuilderApp has CSS defined."""
        manifest_path = Path("/tmp/test.toml")
        options = InventoryRunOptions(manifest=manifest_path, host=None, verbose=False)
        app = InventoryBuilderApp(options)

        assert hasattr(app, "CSS")
        assert "Screen" in app.CSS
        assert "InventoryBuilderApp" in app.CSS


class TestRunTextualApp:
    """Tests for run_textual_app function."""

    @patch("proxmox_cli.textual_app.InventoryBuilderApp")
    def test_run_textual_app_success(self, mock_app_class: Any) -> None:
        """Test run_textual_app with success."""
        manifest_path = Path("/tmp/test.toml")
        options = InventoryRunOptions(manifest=manifest_path, host=None, verbose=False)

        mock_app = mock_app_class.return_value
        mock_app.get_result.return_value = AppResult(exit_code=0)

        exit_code = run_textual_app(options)

        assert exit_code == 0
        mock_app_class.assert_called_once_with(options)
        mock_app.run.assert_called_once()

    @patch("proxmox_cli.textual_app.InventoryBuilderApp")
    def test_run_textual_app_with_error(self, mock_app_class: Any) -> None:
        """Test run_textual_app with error."""
        manifest_path = Path("/tmp/test.toml")
        options = InventoryRunOptions(manifest=manifest_path, host=None, verbose=False)

        mock_app = mock_app_class.return_value
        mock_app.get_result.return_value = AppResult(exit_code=2, message="Error")

        exit_code = run_textual_app(options)

        assert exit_code == 2

    @patch("proxmox_cli.textual_app.InventoryBuilderApp")
    def test_run_textual_app_with_abort(self, mock_app_class: Any) -> None:
        """Test run_textual_app with TextualAbort."""
        manifest_path = Path("/tmp/test.toml")
        options = InventoryRunOptions(manifest=manifest_path, host=None, verbose=False)

        mock_app = mock_app_class.return_value
        mock_app.run.side_effect = TextualAbort("User aborted")

        exit_code = run_textual_app(options)

        assert exit_code == 1

    @patch("proxmox_cli.textual_app.InventoryBuilderApp")
    @patch("logging_utils.configure_logging")
    def test_run_textual_app_with_exception(
        self,
        mock_configure_logging: Any,
        mock_app_class: Any,
    ) -> None:
        """Test run_textual_app with unexpected exception."""
        manifest_path = Path("/tmp/test.toml")
        options = InventoryRunOptions(manifest=manifest_path, host=None, verbose=False)

        mock_app = mock_app_class.return_value
        mock_app.run.side_effect = Exception("Unexpected error")

        exit_code = run_textual_app(options)

        assert exit_code == 2
        mock_configure_logging.assert_called_once_with(False)
