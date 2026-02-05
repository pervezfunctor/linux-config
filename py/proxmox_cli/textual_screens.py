"""Textual screens for Proxmox inventory builder.

This module defines all the screens used in the Textual TUI application,
including welcome, host selection, host configuration, discovery, guest
configuration, and summary screens.
"""

from __future__ import annotations

from typing import TYPE_CHECKING, ClassVar, cast

from textual.containers import Center, Horizontal, Vertical, VerticalScroll
from textual.screen import Screen
from textual.widgets import (
    Button,
    DataTable,
    Footer,
    Header,
    Input,
    Label,
    ProgressBar,
    Static,
    Switch,
)

from proxmox_inventory_builder import ManagedGuest
from proxmox_manifest_models import HostForm

if TYPE_CHECKING:
    from textual.app import ComposeResult

    from proxmox_cli.textual_app import InventoryBuilderApp
else:
    from collections.abc import Generator as ComposeResult


class ProxmoxBaseScreen(Screen[None]):
    """Base screen for Proxmox inventory builder."""

    @property
    def app(self) -> InventoryBuilderApp:
        """Type-safe access to the application."""
        return cast("InventoryBuilderApp", super().app)

class WelcomeScreen(ProxmoxBaseScreen):
    """Welcome screen for the inventory builder.

    This screen displays a welcome message and allows the user to proceed
    to host selection or exit.
    """

    BINDINGS: ClassVar[list[tuple[str, str, str]]] = [("enter", "proceed", "Proceed"), ("q", "quit", "Quit")]

    def compose(self) -> ComposeResult:
        """Compose the welcome screen UI."""
        app = self.app

        yield Header()
        with Vertical():
            yield Center(Static("Proxmox Inventory Builder", classes="title"))
            yield Center(
                Static(
                    f"Manifest: {app.manifest_path}",
                    classes="info",
                )
            )
            yield Center(
                Static(
                    f"Hosts in manifest: {len(app.manifest_state.hosts) if app.manifest_state else 0}",
                    classes="info",
                )
            )
            yield Center(
                Static(
                    "Press Enter to continue or Q to quit",
                    classes="info",
                )
            )
        yield Footer()

    def action_proceed(self) -> None:
        """Proceed to host selection screen."""
        app = self.app
        self.dismiss()
        app.push_screen(HostSelectScreen())


class HostSelectScreen(ProxmoxBaseScreen):
    """Screen for selecting a host or creating a new one.

    This screen displays a list of existing hosts and allows the user to
    select one to edit or create a new host entry.
    """

    BINDINGS: ClassVar[list[tuple[str, str, str]]] = [("q", "quit", "Quit"), ("escape", "cancel", "Cancel")]

    def compose(self) -> ComposeResult:
        """Compose the host selection screen UI."""
        yield Header()
        with Vertical():
            yield Static("Select a Host", classes="title")
            yield DataTable()
            with Horizontal():
                yield Button("Select", id="select_button", variant="primary")
                yield Button("Add New Host", id="add_button", variant="success")
                yield Button("Cancel", id="cancel_button", variant="default")
        yield Footer()

    def on_mount(self) -> None:
        """Handle screen mount event."""
        table: DataTable[str] = self.query_one(DataTable)
        table.add_column("Name", key="name")
        table.add_column("Host", key="host")
        table.add_column("User", key="user")

        app = self.app
        if app.manifest_state:
            for host in app.manifest_state.hosts:
                table.add_row(
                    host.name,
                    host.host,
                    host.user or app.manifest_state.defaults.user,
                )

    def on_button_pressed(self, event: Button.Pressed) -> None:
        """Handle button press events."""
        app = self.app

        if event.button.id == "add_button":
            app.is_new_host = True
            self.dismiss()
            app.push_screen(HostConfigScreen(is_new_host=True))
        elif event.button.id == "cancel_button":
            app.set_result(1, "Cancelled by user")
            app.exit()
        elif event.button.id == "select_button":
            table: DataTable[str] = self.query_one(DataTable)
            if table.cursor_row is not None:
                row_key = table.get_row_at(table.cursor_row)[0]
                app.is_new_host = False
                if app.manifest_state:
                    for host in app.manifest_state.hosts:
                        if host.name == row_key:
                            app.selected_host = host
                            break
                self.dismiss()
                app.push_screen(DiscoveryScreen())

    def action_cancel(self) -> None:
        """Cancel the operation."""
        app = self.app
        app.set_result(1, "Cancelled by user")
        app.exit()


class HostConfigScreen(ProxmoxBaseScreen):
    """Screen for configuring host details.

    This screen collects all required and optional host configuration fields,
    including name, hostname, SSH user, guest SSH args, dry-run toggle, and
    max parallel operations.
    """

    BINDINGS: ClassVar[list[tuple[str, str, str]]] = [
        ("ctrl+s", "save", "Save"),
        ("escape", "cancel", "Cancel"),
    ]

    def __init__(self, is_new_host: bool = False) -> None:
        """Initialize the host config screen.

        Args:
            is_new_host: Whether this is a new host being created.
        """
        super().__init__()
        self.is_new_host = is_new_host

    def compose(self) -> ComposeResult:
        """Compose the host configuration screen UI."""
        yield Header()
        with VerticalScroll():
            yield Static("Host Configuration", classes="title")
            yield Label("Host entry name (required):")
            yield Input(placeholder="my-proxmox-host", id="host_name")
            yield Label("Proxmox hostname or IP (required):")
            yield Input(placeholder="proxmox.example.com", id="host_address")
            yield Label("SSH user (optional):")
            yield Input(placeholder="root", id="ssh_user")
            yield Label("Additional SSH args for guests (comma-separated):")
            yield Input(placeholder="-o StrictHostKeyChecking=no", id="guest_ssh_args")
            with Horizontal():
                yield Label("Enable dry-run:")
                yield Switch(value=False, id="dry_run")
            yield Label("Max parallel guest actions:")
            yield Input(placeholder="2", id="max_parallel")
            with Horizontal():
                yield Button("Save", id="save_button", variant="primary")
                yield Button("Cancel", id="cancel_button", variant="default")
        yield Footer()

    def on_mount(self) -> None:
        """Handle screen mount event."""
        app = self.app

        if not self.is_new_host and app.selected_host:
            host = app.selected_host
            self.query_one("#host_name", Input).value = host.name
            self.query_one("#host_address", Input).value = host.host
            if host.user:
                self.query_one("#ssh_user", Input).value = host.user
            if host.guest_ssh_extra_args:
                self.query_one("#guest_ssh_args", Input).value = ", ".join(host.guest_ssh_extra_args)
            if host.dry_run is not None:
                self.query_one("#dry_run", Switch).value = host.dry_run
            if host.max_parallel is not None:
                self.query_one("#max_parallel", Input).value = str(host.max_parallel)
        elif app.manifest_state:
            defaults = app.manifest_state.defaults
            self.query_one("#ssh_user", Input).value = defaults.user
            self.query_one("#dry_run", Switch).value = defaults.dry_run
            self.query_one("#max_parallel", Input).value = str(defaults.max_parallel)

    def on_button_pressed(self, event: Button.Pressed) -> None:
        """Handle button press events."""
        if event.button.id == "save_button":
            self.action_save()
        elif event.button.id == "cancel_button":
            self.action_cancel()

    def action_save(self) -> None:
        """Save the host configuration."""
        app = self.app

        name = self.query_one("#host_name", Input).value.strip()
        host = self.query_one("#host_address", Input).value.strip()
        user = self.query_one("#ssh_user", Input).value.strip() or None
        guest_ssh_args = self.query_one("#guest_ssh_args", Input).value.strip()
        dry_run = self.query_one("#dry_run", Switch).value
        max_parallel = self.query_one("#max_parallel", Input).value.strip()

        # Validate required fields
        if not name:
            self.query_one(Static).update("[bold red]Host name is required[/]")
            return
        if not host:
            self.query_one(Static).update("[bold red]Host address is required[/]")
            return

        # Parse guest SSH args
        guest_ssh_args_list = [arg.strip() for arg in guest_ssh_args.split(",") if arg.strip()] or None

        # Parse max parallel
        try:
            max_parallel_int = int(max_parallel) if max_parallel else 2
        except ValueError:
            self.query_one(Static).update("[bold red]Max parallel must be a number[/]")
            return

        # Create or update host
        host_form = HostForm(
            name=name,
            host=host,
            user=user,
            guest_ssh_extra_args=guest_ssh_args_list,
            max_parallel=max_parallel_int,
            dry_run=dry_run,
        )

        app.selected_host = host_form
        if self.is_new_host and app.manifest_state:
            app.manifest_state.hosts.append(host_form)

        self.dismiss()
        app.push_screen(DiscoveryScreen())

    def action_cancel(self) -> None:
        """Cancel the operation."""
        app = self.app
        if self.is_new_host:
            self.dismiss()
            app.push_screen(HostSelectScreen())
        else:
            app.set_result(1, "Cancelled by user")
            app.exit()


class DiscoveryScreen(ProxmoxBaseScreen):
    """Screen for discovering guests on the selected host.

    This screen displays progress during the SSH-based discovery of VMs
    and containers on the Proxmox host.
    """

    BINDINGS: ClassVar[list[tuple[str, str, str]]] = [("q", "quit", "Quit")]

    def compose(self) -> ComposeResult:
        """Compose the discovery screen UI."""
        yield Header()
        with Vertical():
            yield Static("Discovering Guests", classes="title")
            yield Static("Connecting to host and querying inventory...", classes="info")
            yield ProgressBar(total=100, id="progress_bar")
            yield Static("", id="status_message", classes="info")
        yield Footer()

    def on_mount(self) -> None:
        """Handle screen mount event."""
        import asyncio

        async def run_discovery() -> None:
            app = self.app

            progress = self.query_one("#progress_bar", ProgressBar)
            status = self.query_one("#status_message", Static)

            try:
                status.update("Initializing SSH connection...")
                progress.advance(10)

                from proxmox_inventory_builder import discover_inventory

                if app.selected_host and app.manifest_state:
                    discoveries = await discover_inventory(
                        app.selected_host,
                        app.manifest_state.defaults,
                    )
                    app.guest_discoveries = discoveries
                    progress.advance(90)

                    status.update(f"Discovered {len(discoveries)} guests")

                    # Short delay before proceeding
                    await asyncio.sleep(0.5)

                    self.dismiss()
                    app.push_screen(GuestConfigScreen())

            except Exception as exc:
                status.update(f"[bold red]Error: {exc}[/]")
                import structlog

                logger = structlog.get_logger(__name__)
                logger.error("Discovery failed", exc_info=exc)

                await asyncio.sleep(2)
                app.set_result(2, f"Discovery failed: {exc}")
                app.exit()

        self._discovery_task = asyncio.create_task(run_discovery())


class GuestConfigScreen(ProxmoxBaseScreen):
    """Screen for configuring guest management settings.

    This screen displays discovered guests and allows the user to toggle
    the managed status and add notes for each guest.
    """

    BINDINGS: ClassVar[list[tuple[str, str, str]]] = [
        ("ctrl+s", "save", "Save All"),
        ("escape", "cancel", "Cancel"),
    ]

    def compose(self) -> ComposeResult:
        """Compose the guest configuration screen UI."""
        yield Header()
        with Vertical():
            yield Static("Configure Guests", classes="title")
            yield DataTable(id="guest_table")
            yield Label("Notes for selected guest:")
            yield Input(placeholder="Enter notes here...", id="guest_notes")
            with Horizontal():
                yield Button("Save All", id="save_button", variant="primary")
                yield Button("Cancel", id="cancel_button", variant="default")
        yield Footer()

    def on_mount(self) -> None:
        """Handle screen mount event."""
        table: DataTable[str] = self.query_one("#guest_table", DataTable)
        table.add_column("Type", key="kind")
        table.add_column("ID", key="id")
        table.add_column("Name", key="name")
        table.add_column("Status", key="status")
        table.add_column("IP", key="ip")
        table.add_column("Managed", key="managed")

        app = self.app

        # Load existing guest data if available
        from proxmox_inventory_builder import load_existing_guest_map

        existing_map = {}
        if app.selected_host:
            existing_map = load_existing_guest_map(app.selected_host)

        for guest in app.guest_discoveries:
            existing = existing_map.get((guest.kind, guest.identifier), {})
            managed = bool(existing.get("managed", True))
            table.add_row(
                guest.kind.upper(),
                guest.identifier,
                guest.name,
                guest.status,
                guest.ip or "N/A",
                "Yes" if managed else "No",
                key=f"{guest.kind}:{guest.identifier}",
            )

        # Store managed status and notes for each guest
        self.guest_managed: dict[str, bool] = {}
        self.guest_notes: dict[str, str | None] = {}
        for guest in app.guest_discoveries:
            key = f"{guest.kind}:{guest.identifier}"
            existing = existing_map.get((guest.kind, guest.identifier), {})
            self.guest_managed[key] = bool(existing.get("managed", True))
            self.guest_notes[key] = existing.get("notes")

    def on_data_table_row_selected(self, event: DataTable.RowSelected) -> None:
        """Handle row selection in the guest table."""
        row_key = str(event.row_key.value) if event.row_key else None
        if row_key:
            notes = self.guest_notes.get(row_key)
            self.query_one("#guest_notes", Input).value = notes or ""

    def on_input_submitted(self, event: Input.Submitted) -> None:
        """Handle input submission (notes field)."""
        if event.input.id == "guest_notes":
            table: DataTable[str] = self.query_one("#guest_table", DataTable)
            if table.cursor_row is not None:
                row = table.get_row_at(table.cursor_row)
                if row:
                    key = f"{row[0].lower()}:{row[1]}"  # kind:id from the row
                    self.guest_notes[key] = event.value or None

    def on_button_pressed(self, event: Button.Pressed) -> None:
        """Handle button press events."""
        if event.button.id == "save_button":
            self.action_save()
        elif event.button.id == "cancel_button":
            self.action_cancel()

    def action_save(self) -> None:
        """Save all guest configurations."""
        app = self.app
        assert app.selected_host is not None

        from datetime import UTC, datetime

        entries: list[ManagedGuest] = []
        for guest in app.guest_discoveries:
            key = f"{guest.kind}:{guest.identifier}"
            entry = ManagedGuest(
                discovery=guest,
                managed=self.guest_managed.get(key, True),
                notes=self.guest_notes.get(key),
                last_checked=datetime.now(UTC).isoformat(),
            )
            entries.append(entry)

        app.managed_guests = entries

        # Update host inventory
        if app.selected_host:
            from proxmox_inventory_builder import update_host_inventory

            update_host_inventory(app.selected_host, entries)

        # Save manifest
        if app.manifest_state:
            from proxmox_inventory_builder import save_manifest

            save_manifest(app.manifest_state, app.manifest_path)

        app.set_result(0, f"Configured {len(entries)} guests for host {app.selected_host.name}")
        self.dismiss()
        app.push_screen(SummaryScreen())

    def action_cancel(self) -> None:
        """Cancel the operation."""
        app = self.app
        app.set_result(1, "Cancelled by user")
        app.exit()


class SummaryScreen(ProxmoxBaseScreen):
    """Screen displaying the summary of completed operations.

    This screen shows the results of the inventory building process and
    allows the user to exit or start over.
    """

    BINDINGS: ClassVar[list[tuple[str, str, str]]] = [("enter", "exit", "Exit"), ("r", "restart", "Restart")]

    def compose(self) -> ComposeResult:
        """Compose the summary screen UI."""
        yield Header()
        with Vertical():
            yield Static("Summary", classes="title")
            yield Static("", id="summary_message", classes="success")
            yield Static("", id="details_message", classes="info")
            with Horizontal():
                yield Button("Exit", id="exit_button", variant="primary")
                yield Button("Start Over", id="restart_button", variant="default")
        yield Footer()

    def on_mount(self) -> None:
        """Handle screen mount event."""
        app = self.app

        result = app.get_result()
        if result.message:
            self.query_one("#summary_message", Static).update(f"[bold green]{result.message}[/]")

        if app.selected_host:
            self.query_one("#details_message", Static).update(
                f"Host: {app.selected_host.name} ({app.selected_host.host})\n"
                f"Guests configured: {len(app.managed_guests)}"
            )

    def on_button_pressed(self, event: Button.Pressed) -> None:
        """Handle button press events."""
        if event.button.id == "exit_button":
            self.action_exit()
        elif event.button.id == "restart_button":
            self.action_restart()

    def action_exit(self) -> None:
        """Exit the application."""
        app = self.app
        app.exit()

    def action_restart(self) -> None:
        """Restart the application."""
        app = self.app
        self.dismiss()
        app.push_screen(WelcomeScreen())
