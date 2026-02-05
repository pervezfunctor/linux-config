"""Custom Textual widgets for Proxmox inventory builder.

This module provides custom widgets that extend Textual's built-in widgets
with validation and behavior specific to the Proxmox inventory builder workflow.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from textual import on
from textual.containers import Horizontal, Vertical
from textual.validation import ValidationResult, Validator
from textual.widgets import Input, Label, Static, Switch

if TYPE_CHECKING:
    from typing import Any


class RequiredValidator(Validator):
    """Validator that requires non-empty input."""

    def validate(self, value: str) -> ValidationResult:
        """Validate that the input is not empty.

        Args:
            value: The input value to validate.

        Returns:
            ValidationResult indicating success or failure.
        """
        if value.strip():
            return self.success()
        return self.failure("This field is required")


class CSVValidator(Validator):
    """Validator for comma-separated value lists."""

    def validate(self, value: str) -> ValidationResult:
        """Validate CSV input.

        Args:
            value: The input value to validate.

        Returns:
            ValidationResult indicating success or failure.
        """
        if not value.strip():
            return self.success()  # Empty is allowed

        items = [item.strip() for item in value.split(",")]
        if not all(items):
            return self.failure("CSV values cannot be empty")
        return self.success()


class IntegerValidator(Validator):
    """Validator for positive integer input."""

    def __init__(self, min_value: int = 1) -> None:
        """Initialize the integer validator.

        Args:
            min_value: Minimum allowed value (default 1).
        """
        super().__init__()
        self.min_value = min_value

    def validate(self, value: str) -> ValidationResult:
        """Validate integer input.

        Args:
            value: The input value to validate.

        Returns:
            ValidationResult indicating success or failure.
        """
        if not value.strip():
            return self.failure("This field is required")

        try:
            int_value = int(value)
        except ValueError:
            return self.failure("Must be a valid integer")

        if int_value < self.min_value:
            return self.failure(f"Must be at least {self.min_value}")

        return self.success()


class RequiredInput(Input):
    """Input widget that requires non-empty values."""

    def __init__(self, **kwargs: Any) -> None:
        """Initialize the required input widget.

        Args:
            **kwargs: Additional arguments passed to Input.
        """
        kwargs.setdefault("validators", RequiredValidator())
        super().__init__(**kwargs)


class OptionalInput(Input):
    """Input widget that allows empty values."""

    def __init__(self, **kwargs: Any) -> None:
        """Initialize the optional input widget.

        Args:
            **kwargs: Additional arguments passed to Input.
        """
        super().__init__(**kwargs)


class CSVInput(Input):
    """Input widget for comma-separated values."""

    def __init__(self, **kwargs: Any) -> None:
        """Initialize the CSV input widget.

        Args:
            **kwargs: Additional arguments passed to Input.
        """
        kwargs.setdefault("validators", CSVValidator())
        super().__init__(**kwargs)


class IntInput(Input):
    """Input widget for positive integers."""

    def __init__(self, min_value: int = 1, **kwargs: Any) -> None:
        """Initialize the integer input widget.

        Args:
            min_value: Minimum allowed value (default 1).
            **kwargs: Additional arguments passed to Input.
        """
        kwargs.setdefault("validators", IntegerValidator(min_value))
        super().__init__(**kwargs)


class BoolSwitch(Switch):
    """Switch widget for boolean values."""

    def __init__(self, default: bool = False, **kwargs: Any) -> None:
        """Initialize the boolean switch widget.

        Args:
            default: Default value (default False).
            **kwargs: Additional arguments passed to Switch.
        """
        super().__init__(value=default, **kwargs)


class OptionalBoolSwitch(Switch):
    """Switch widget for optional boolean values."""

    def __init__(self, current: bool | None = None, **kwargs: Any) -> None:
        """Initialize the optional boolean switch widget.

        Args:
            current: Current value (None means inherit).
            **kwargs: Additional arguments passed to Switch.
        """
        super().__init__(value=current if current is not None else False, **kwargs)
        self._inherit_mode = current is None

    @property
    def is_inherit_mode(self) -> bool:
        """Check if the switch is in inherit mode.

        Returns:
            True if in inherit mode, False otherwise.
        """
        return self._inherit_mode

    def toggle_inherit(self) -> None:
        """Toggle between inherit mode and explicit value."""
        self._inherit_mode = not self._inherit_mode
        if self._inherit_mode:
            self.value = False
        else:
            self.value = True


class PathInput(Input):
    """Input widget for filesystem paths."""

    def __init__(self, **kwargs: Any) -> None:
        """Initialize the path input widget.

        Args:
            **kwargs: Additional arguments passed to Input.
        """
        super().__init__(**kwargs)


class FormField(Vertical):
    """A form field with label, input, and error message."""

    def __init__(
        self,
        label: str,
        input_widget: Input,
        required: bool = True,
        **kwargs: Any,
    ) -> None:
        """Initialize the form field.

        Args:
            label: Field label text.
            input_widget: The input widget to use.
            required: Whether the field is required.
            **kwargs: Additional arguments passed to Vertical.
        """
        super().__init__(**kwargs)
        self.label_text = label
        self.input_widget = input_widget
        self.required = required

    def compose(self) -> Any:
        """Compose the form field."""
        label = self.label_text
        if self.required:
            label += " *"
        yield Label(label)
        yield self.input_widget
        yield Static("", id=f"error_{self.input_widget.id or 'field'}", classes="error")

    @on(Input.Changed)
    def on_input_changed(self, event: Input.Changed) -> None:
        """Handle input change events."""
        error_id = f"error_{event.input.id or 'field'}"
        error_widget = self.query_one(f"#{error_id}", Static)

        if event.validation_result and not event.validation_result.is_valid:
            error_widget.update(f"[bold red]{event.validation_result.failure_descriptions[0]}[/]")
        else:
            error_widget.update("")


class ManagedGuestRow(Horizontal):
    """A row displaying a guest with managed toggle and notes."""

    def __init__(
        self,
        guest_kind: str,
        guest_id: str,
        guest_name: str,
        guest_status: str,
        guest_ip: str | None,
        managed: bool = True,
        notes: str | None = None,
        **kwargs: Any,
    ) -> None:
        """Initialize the managed guest row.

        Args:
            guest_kind: Guest type (vm or ct).
            guest_id: Guest identifier.
            guest_name: Guest name.
            guest_status: Guest status.
            guest_ip: Guest IP address.
            managed: Whether the guest is managed.
            notes: Notes for the guest.
            **kwargs: Additional arguments passed to Horizontal.
        """
        super().__init__(**kwargs)
        self.guest_kind = guest_kind
        self.guest_id = guest_id
        self.guest_name = guest_name
        self.guest_status = guest_status
        self.guest_ip = guest_ip
        self.managed = managed
        self.notes = notes

    def compose(self) -> Any:
        """Compose the managed guest row."""
        kind_prefix = "VM" if self.guest_kind == "vm" else "CT"
        yield Static(
            f"{kind_prefix} {self.guest_name} ({self.guest_id})",
            classes="guest-label",
        )
        yield Static(f"[dim]{self.guest_status}[/]", classes="guest-status")
        if self.guest_ip:
            yield Static(f"[dim]{self.guest_ip}[/]", classes="guest-ip")
        yield BoolSwitch(value=self.managed, id=f"switch_{self.guest_kind}_{self.guest_id}")
        yield Input(
            value=self.notes or "",
            placeholder="Notes...",
            id=f"notes_{self.guest_kind}_{self.guest_id}",
            classes="guest-notes",
        )

    @property
    def is_managed(self) -> bool:
        """Get the managed status.

        Returns:
            True if managed, False otherwise.
        """
        switch = self.query_one(f"#switch_{self.guest_kind}_{self.guest_id}", Switch)
        return switch.value

    @property
    def guest_notes(self) -> str | None:
        """Get the guest notes.

        Returns:
            The notes text or None if empty.
        """
        notes_input = self.query_one(f"#notes_{self.guest_kind}_{self.guest_id}", Input)
        return notes_input.value or None
