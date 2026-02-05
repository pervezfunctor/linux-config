#!/usr/bin/env python3
"""Interactive wizard for managing proxmox_batch manifests."""

from __future__ import annotations

import copy
from pathlib import Path
from typing import cast

import questionary
import structlog
import typer

import proxmox_batch
from logging_utils import configure_logging
from proxmox_batch import ManifestError
from proxmox_manifest import load_manifest_state, write_manifest
from proxmox_manifest_models import DefaultsForm, HostForm, ManifestState
from questionary_prompts import (
    WizardAbort,
    ask_bool,
    ask_csv_list,
    ask_int,
    ask_optional_bool,
    ask_optional_text,
    ask_text,
)

LOGGER = structlog.get_logger(__name__)
app = typer.Typer(add_completion=False, help="Interactive editor for proxmox-hosts manifests.")

_CONFIG_OPTION = typer.Option(
    proxmox_batch.DEFAULT_CONFIG_PATH,
    "--config",
    "-c",
    help="Path to the manifest file",
)
_VERBOSE_OPTION = typer.Option(False, "--verbose", "-v", help="Enable verbose logging")


def _print_cli_notice() -> None:
    questionary.print("Tip: use `proxmoxctl wizard run` for the unified CLI.", style="bold yellow")


def _format_host_label(host: HostForm) -> str:
    return f"{host.name} ({host.host})"


def _clone_host(host: HostForm) -> HostForm:
    return HostForm(
        name=host.name,
        host=host.host,
        user=host.user,
        guest_ssh_extra_args=None if host.guest_ssh_extra_args is None else list(host.guest_ssh_extra_args),
        max_parallel=host.max_parallel,
        dry_run=host.dry_run,
        extras=copy.deepcopy(host.extras),
    )


class ManifestWizard:
    def __init__(self, path: Path, state: ManifestState | None = None) -> None:
        self.path = path
        self.state = state or ManifestState.empty()
        self.dirty = False

    def load(self) -> None:
        if not self.path.exists():
            confirm = questionary.confirm(
                f"Manifest '{self.path}' not found. Create a new manifest?",
                default=True,
            ).ask()
            if confirm is None:
                raise WizardAbort()
            if not confirm:
                raise WizardAbort()
            self.state = ManifestState.empty()
            self.dirty = True
            return
        self.state = load_manifest_state(self.path)

    def run(self) -> None:
        self.load()
        while True:
            choice = questionary.select(
                "Select an action",
                choices=[
                    questionary.Choice("Edit defaults", "defaults"),
                    questionary.Choice("Manage hosts", "hosts"),
                    questionary.Choice("Save and exit", "save"),
                    questionary.Choice("Exit without saving", "exit"),
                ],
            ).ask()
            if choice is None:
                raise WizardAbort()
            if choice == "defaults":
                if self.edit_defaults():
                    self.dirty = True
            elif choice == "hosts":
                if self.manage_hosts():
                    self.dirty = True
            elif choice == "save":
                self.save()
                return
            elif choice == "exit":
                if self.dirty:
                    confirm = questionary.confirm("Discard unsaved changes?", default=False).ask()
                    if not confirm:
                        continue
                return

    def save(self) -> None:
        write_manifest(self.state, self.path)
        self.dirty = False

    def edit_defaults(self) -> bool:
        defaults: DefaultsForm = self.state.defaults
        try:
            defaults.user = ask_text("SSH user", default=defaults.user, required=True)
            defaults.guest_user = ask_text(
                "Guest SSH user",
                default=defaults.guest_user,
                required=True,
            )
            defaults.identity_file = ask_optional_text(
                "Identity file (enter 'none' to clear)",
                default=defaults.identity_file,
                clear_word="none",
            )
            defaults.guest_identity_file = ask_optional_text(
                "Guest identity file (enter 'none' to clear)",
                default=defaults.guest_identity_file,
                clear_word="none",
            )
            ssh_list = ask_csv_list(
                "SSH extra args",
                current=defaults.ssh_extra_args,
                allow_inherit=False,
            )
            defaults.ssh_extra_args = ssh_list if ssh_list is not None else []
            guest_ssh_list = ask_csv_list(
                "Guest SSH extra args",
                current=defaults.guest_ssh_extra_args,
                allow_inherit=False,
            )
            defaults.guest_ssh_extra_args = guest_ssh_list if guest_ssh_list is not None else []
            max_parallel_value = ask_int(
                "Max parallel hosts",
                default=defaults.max_parallel,
                required=True,
            )
            defaults.max_parallel = cast(int, max_parallel_value)
            defaults.dry_run = ask_bool(
                "Enable dry-run by default?",
                default=defaults.dry_run,
            )
        except WizardAbort:
            return False
        return True

    def manage_hosts(self) -> bool:
        dirty = False
        while True:
            choice = questionary.select(
                "Host manager",
                choices=[
                    questionary.Choice("Add host", "add"),
                    questionary.Choice("Edit host", "edit"),
                    questionary.Choice("Duplicate host", "duplicate"),
                    questionary.Choice("Delete host", "delete"),
                    questionary.Choice("Back", "back"),
                ],
            ).ask()
            if choice is None:
                raise WizardAbort()
            if choice == "add":
                dirty |= self.add_host()
            elif choice == "edit":
                dirty |= self.edit_host()
            elif choice == "duplicate":
                dirty |= self.duplicate_host()
            elif choice == "delete":
                dirty |= self.delete_host()
            elif choice == "back":
                return dirty

    def _select_host_index(self, prompt: str) -> int | None:
        if not self.state.hosts:
            questionary.print("No hosts defined yet.", style="bold yellow")
            return None
        choice = questionary.select(
            prompt,
            choices=[
                questionary.Choice(_format_host_label(host), idx) for idx, host in enumerate(self.state.hosts)
            ],
        ).ask()
        if choice is None:
            raise WizardAbort()
        return int(choice)

    def add_host(self) -> bool:
        host = HostForm(
            name="",
            host="",
            extras={},
        )
        return self._edit_host_form(host, is_new=True)

    def edit_host(self) -> bool:
        index = self._select_host_index("Select a host to edit")
        if index is None:
            return False
        host = _clone_host(self.state.hosts[index])
        if self._edit_host_form(host, is_new=False):
            self.state.hosts[index] = host
            return True
        return False

    def duplicate_host(self) -> bool:
        index = self._select_host_index("Select a host to duplicate")
        if index is None:
            return False
        host = _clone_host(self.state.hosts[index])
        host.name = f"{host.name}-copy"
        if self._edit_host_form(host, is_new=True):
            self.state.hosts.append(host)
            return True
        return False

    def delete_host(self) -> bool:
        index = self._select_host_index("Select a host to delete")
        if index is None:
            return False
        host = self.state.hosts[index]
        confirm = questionary.confirm(f"Delete host '{host.name}'?", default=False).ask()
        if confirm:
            self.state.hosts.pop(index)
            return True
        return False

    def _edit_host_form(self, host: HostForm, *, is_new: bool) -> bool:
        defaults: DefaultsForm = self.state.defaults
        try:
            host.name = self._ask_unique_name(host.name, current=host.name)
            host.host = ask_text("Host address", default=host.host, required=True)
            host.user = self._ask_inheritable_text(
                "SSH user",
                current=host.user,
                inherit_value=defaults.user,
            )
            host.guest_ssh_extra_args = self._ask_inheritable_list(
                "Guest SSH extra args",
                current=host.guest_ssh_extra_args,
                inherit_from=defaults.guest_ssh_extra_args,
            )
            host.max_parallel = self._ask_inheritable_int(
                "Max parallel hosts",
                current=host.max_parallel,
                inherit_value=defaults.max_parallel,
            )
            host.dry_run = self._ask_inheritable_bool(
                "Force dry-run",
                current=host.dry_run,
                inherit_value=defaults.dry_run,
            )
        except WizardAbort:
            return False

        if is_new:
            self.state.hosts.append(host)
        return True

    def _ask_unique_name(self, proposed: str, *, current: str | None) -> str:
        while True:
            value = ask_text("Host name", default=proposed, required=True)
            if value == current:
                return value
            if any(existing.name == value for existing in self.state.hosts):
                questionary.print("Host name already exists.", style="bold red")
                continue
            return value

    def _ask_inheritable_text(
        self,
        label: str,
        *,
        current: str | None,
        inherit_value: str | None,
    ) -> str | None:
        inherit_word = "inherit"
        if inherit_value is None:
            hint = f"type '{inherit_word}' to inherit defaults"
        else:
            hint = f"type '{inherit_word}' to inherit {inherit_value!r}"
        prompt = f"{label} ({hint}; leave blank to keep current)"
        return ask_optional_text(
            prompt,
            default=current or None,
            inherit_word=inherit_word,
        )

    def _ask_inheritable_list(
        self,
        label: str,
        *,
        current: list[str] | None,
        inherit_from: list[str],
    ) -> list[str] | None:
        inherit_word = "inherit"
        prompt = f"{label} (inherit -> {inherit_from!r})"
        return ask_csv_list(
            prompt,
            current=current,
            allow_inherit=True,
            inherit_word=inherit_word,
        )

    def _ask_inheritable_int(
        self,
        label: str,
        *,
        current: int | None,
        inherit_value: int,
    ) -> int | None:
        prompt = f"{label} (inherit -> {inherit_value})"
        return ask_int(prompt, default=current, required=False, allow_inherit=True)

    def _ask_inheritable_bool(
        self,
        label: str,
        *,
        current: bool | None,
        inherit_value: bool,
    ) -> bool | None:
        hint = f"inherit -> {inherit_value}"
        return ask_optional_bool(f"{label} ({hint})", current=current)


def run_wizard(manifest_path: Path, *, verbose: bool) -> int:
    configure_logging(verbose)
    wizard = ManifestWizard(manifest_path)
    try:
        wizard.run()
    except WizardAbort:
        questionary.print("Aborted.", style="bold red")
        return 1
    except ManifestError as exc:
        LOGGER.error("manifest-error", error=str(exc))
        return 1
    return 0


@app.command("run")
def cli_run(
    config: Path = _CONFIG_OPTION,
    verbose: bool = _VERBOSE_OPTION,
) -> None:
    _print_cli_notice()
    exit_code = run_wizard(config, verbose=verbose)
    raise typer.Exit(exit_code)


def main() -> None:
    app()


if __name__ == "__main__":
    main()
