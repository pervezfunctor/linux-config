"""Textual TUI application for Proxmox inventory builder.

This module provides a modern Terminal User Interface (TUI) for the Proxmox
inventory builder, replacing the Questionary-based CLI with a rich, interactive
experience.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING, ClassVar

from textual.app import App, ComposeResult
from textual.binding import BindingType
from textual.containers import Center, Vertical
from textual.widgets import Footer, Header, Static

from proxmox_inventory_builder import (
    GuestDiscovery,
    InventoryRunOptions,
    ManagedGuest,
)
from proxmox_manifest_models import HostForm, ManifestState

if TYPE_CHECKING:
    pass


class TextualAbort(RuntimeError):
    """Raised when the user aborts the Textual wizard."""


@dataclass(frozen=True)
class AppResult:
    """Result of the Textual application execution."""

    exit_code: int
    message: str | None = None


class InventoryBuilderApp(App[None]):
    """Main Textual application for Proxmox inventory builder.

    This app manages the overall workflow for building Proxmox host manifests,
    including host selection, configuration, guest discovery, and guest management.
    """

    CSS = """
    Screen {
        background: $surface;
    }
    InventoryBuilderApp {
        background: $surface;
    }
    .title {
        text-align: center;
        text-style: bold;
        color: $primary;
    }
    .notice {
        text-align: center;
        color: $warning;
        text-style: bold;
    }
    .success {
        text-align: center;
        color: $success;
        text-style: bold;
    }
    .error {
        text-align: center;
        color: $error;
        text-style: bold;
    }
    .info {
        text-align: center;
        color: $text-muted;
    }
    """

    BINDINGS: ClassVar[list[BindingType]] = [
        ("q", "quit", "Quit"),
        ("ctrl+c", "quit", "Quit"),
    ]

    def __init__(self, options: InventoryRunOptions) -> None:
        """Initialize the inventory builder app.

        Args:
            options: Runtime options for the inventory builder.
        """
        super().__init__()
        self.options = options
        self.manifest_path: Path = options.manifest
        self.manifest_state: ManifestState | None = None
        self.selected_host: HostForm | None = None
        self.guest_discoveries: list[GuestDiscovery] = []
        self.managed_guests: list[ManagedGuest] = []
        self.is_new_host: bool = False
        self._result: AppResult | None = None

    def compose(self) -> ComposeResult:
        """Compose the initial UI."""
        yield Header()
        yield Vertical(
            Center(
                Static("Loading...", classes="info"),
            ),
        )
        yield Footer()

    def on_mount(self) -> None:
        """Handle app mount event."""
        self._load_manifest_and_start()

    def _load_manifest_and_start(self) -> None:
        """Load the manifest and start the welcome screen."""
        from proxmox_inventory_builder import load_manifest

        try:
            self.manifest_state = load_manifest(self.manifest_path)
            self._push_welcome_screen()
        except Exception as exc:
            self._result = AppResult(exit_code=2, message=f"Failed to load manifest: {exc}")
            self.exit()

    def _push_welcome_screen(self) -> None:
        """Push the welcome screen."""
        from textual_screens import WelcomeScreen

        self.push_screen(WelcomeScreen())

    def set_result(self, exit_code: int, message: str | None = None) -> None:
        """Set the application result.

        Args:
            exit_code: The exit code to return.
            message: Optional message to display.
        """
        self._result = AppResult(exit_code=exit_code, message=message)

    def get_result(self) -> AppResult:
        """Get the application result.

        Returns:
            The application result.

        Raises:
            RuntimeError: If no result has been set.
        """
        if self._result is None:
            raise RuntimeError("No result set for the application")
        return self._result


def run_textual_app(options: InventoryRunOptions) -> int:
    """Run the Textual application.

    Args:
        options: Runtime options for the inventory builder.

    Returns:
        The exit code from the application.
    """
    app = InventoryBuilderApp(options)
    try:
        app.run()
        result = app.get_result()
        return result.exit_code
    except TextualAbort:
        return 1
    except Exception as exc:
        import structlog

        from logging_utils import configure_logging

        configure_logging(options.verbose)
        logger = structlog.get_logger(__name__)
        logger.error("Unexpected error in Textual app", exc_info=exc)
        return 2
