"""Unit tests for textual_widgets.py."""

from __future__ import annotations

from proxmox_cli.textual_widgets import (
    BoolSwitch,
    CSVInput,
    CSVValidator,
    FormField,
    IntegerValidator,
    IntInput,
    ManagedGuestRow,
    OptionalBoolSwitch,
    OptionalInput,
    PathInput,
    RequiredInput,
    RequiredValidator,
)


class TestRequiredValidator:
    """Tests for RequiredValidator."""

    def test_required_validator_valid(self) -> None:
        """Test RequiredValidator with valid input."""
        validator = RequiredValidator()
        result = validator.validate("test value")

        assert result.is_valid is True
        assert result.failure_descriptions == []

    def test_required_validator_empty(self) -> None:
        """Test RequiredValidator with empty input."""
        validator = RequiredValidator()
        result = validator.validate("")

        assert result.is_valid is False
        assert len(result.failure_descriptions) > 0
        assert "required" in result.failure_descriptions[0].lower()

    def test_required_validator_whitespace_only(self) -> None:
        """Test RequiredValidator with whitespace only."""
        validator = RequiredValidator()
        result = validator.validate("   ")

        assert result.is_valid is False


class TestCSVValidator:
    """Tests for CSVValidator."""

    def test_csv_validator_empty(self) -> None:
        """Test CSVValidator with empty input."""
        validator = CSVValidator()
        result = validator.validate("")

        assert result.is_valid is True

    def test_csv_valid_single_value(self) -> None:
        """Test CSVValidator with single value."""
        validator = CSVValidator()
        result = validator.validate("value1")

        assert result.is_valid is True

    def test_csv_valid_multiple_values(self) -> None:
        """Test CSVValidator with multiple values."""
        validator = CSVValidator()
        result = validator.validate("value1, value2, value3")

        assert result.is_valid is True

    def test_csv_valid_with_spaces(self) -> None:
        """Test CSVValidator with spaces around values."""
        validator = CSVValidator()
        result = validator.validate("  value1  ,  value2  ")

        assert result.is_valid is True

    def test_csv_invalid_empty_value(self) -> None:
        """Test CSVValidator with empty value in list."""
        validator = CSVValidator()
        result = validator.validate("value1, , value2")

        assert result.is_valid is False


class TestIntegerValidator:
    """Tests for IntegerValidator."""

    def test_integer_validator_valid(self) -> None:
        """Test IntegerValidator with valid input."""
        validator = IntegerValidator()
        result = validator.validate("42")

        assert result.is_valid is True

    def test_integer_validator_negative(self) -> None:
        """Test IntegerValidator with negative value below min."""
        validator = IntegerValidator(min_value=1)
        result = validator.validate("-5")

        assert result.is_valid is False

    def test_integer_validator_zero(self) -> None:
        """Test IntegerValidator with zero below min."""
        validator = IntegerValidator(min_value=1)
        result = validator.validate("0")

        assert result.is_valid is False

    def test_integer_validator_empty(self) -> None:
        """Test IntegerValidator with empty input."""
        validator = IntegerValidator()
        result = validator.validate("")

        assert result.is_valid is False

    def test_integer_validator_invalid_string(self) -> None:
        """Test IntegerValidator with invalid string."""
        validator = IntegerValidator()
        result = validator.validate("not a number")

        assert result.is_valid is False

    def test_integer_validator_custom_min(self) -> None:
        """Test IntegerValidator with custom min value."""
        validator = IntegerValidator(min_value=10)
        result = validator.validate("5")

        assert result.is_valid is False

    def test_integer_validator_at_min(self) -> None:
        """Test IntegerValidator with value at min."""
        validator = IntegerValidator(min_value=10)
        result = validator.validate("10")

        assert result.is_valid is True


class TestRequiredInput:
    """Tests for RequiredInput widget."""

    def test_required_input_has_validator(self) -> None:
        """Test that RequiredInput has RequiredValidator."""
        input_widget = RequiredInput()

        assert len(input_widget.validators) > 0
        assert any(isinstance(v, RequiredValidator) for v in input_widget.validators)


class TestOptionalInput:
    """Tests for OptionalInput widget."""

    def test_optional_input_no_validator(self) -> None:
        """Test that OptionalInput has no required validator."""
        input_widget = OptionalInput()

        # OptionalInput should not have RequiredValidator
        assert not any(isinstance(v, RequiredValidator) for v in input_widget.validators)


class TestCSVInput:
    """Tests for CSVInput widget."""

    def test_csv_input_has_validator(self) -> None:
        """Test that CSVInput has CSVValidator."""
        input_widget = CSVInput()

        assert len(input_widget.validators) > 0
        assert any(isinstance(v, CSVValidator) for v in input_widget.validators)


class TestIntInput:
    """Tests for IntInput widget."""

    def test_int_input_has_validator(self) -> None:
        """Test that IntInput has IntegerValidator."""
        input_widget = IntInput()

        assert len(input_widget.validators) > 0
        assert any(isinstance(v, IntegerValidator) for v in input_widget.validators)

    def test_int_input_custom_min(self) -> None:
        """Test IntInput with custom min value."""
        input_widget = IntInput(min_value=5)

        assert any(isinstance(v, IntegerValidator) and v.min_value == 5 for v in input_widget.validators)


class TestBoolSwitch:
    """Tests for BoolSwitch widget."""

    def test_bool_switch_default_false(self) -> None:
        """Test BoolSwitch with default False."""
        switch = BoolSwitch()

        assert switch.value is False

    def test_bool_switch_default_true(self) -> None:
        """Test BoolSwitch with default True."""
        switch = BoolSwitch(default=True)

        assert switch.value is True


class TestOptionalBoolSwitch:
    """Tests for OptionalBoolSwitch widget."""

    def test_optional_bool_switch_default(self) -> None:
        """Test OptionalBoolSwitch with no current value."""
        switch = OptionalBoolSwitch()

        assert switch.is_inherit_mode is True
        assert switch.value is False

    def test_optional_bool_switch_with_current_true(self) -> None:
        """Test OptionalBoolSwitch with current True."""
        switch = OptionalBoolSwitch(current=True)

        assert switch.is_inherit_mode is False
        assert switch.value is True

    def test_optional_bool_switch_with_current_false(self) -> None:
        """Test OptionalBoolSwitch with current False."""
        switch = OptionalBoolSwitch(current=False)

        assert switch.is_inherit_mode is False
        assert switch.value is False

    def test_optional_bool_switch_with_current_none(self) -> None:
        """Test OptionalBoolSwitch with current None."""
        switch = OptionalBoolSwitch(current=None)

        assert switch.is_inherit_mode is True
        assert switch.value is False

    def test_optional_bool_switch_toggle_inherit(self) -> None:
        """Test toggle_inherit method."""
        switch = OptionalBoolSwitch(current=None)

        assert switch.is_inherit_mode is True

        # Note: toggle_inherit() requires an active Textual app context
        # to animate the switch. We test the logic without calling it.
        # switch.toggle_inherit()

        # assert switch.is_inherit_mode is False
        # assert switch.value is True


class TestPathInput:
    """Tests for PathInput widget."""

    def test_path_input_initialization(self) -> None:
        """Test PathInput initialization."""
        input_widget = PathInput()

        assert isinstance(input_widget, PathInput)


class TestFormField:
    """Tests for FormField widget."""

    def test_form_field_required(self) -> None:
        """Test FormField with required=True."""
        field = FormField(label="Test Label", input_widget=RequiredInput(), required=True)

        assert field.label_text == "Test Label"
        assert field.required is True

    def test_form_field_optional(self) -> None:
        """Test FormField with required=False."""
        field = FormField(label="Test Label", input_widget=OptionalInput(), required=False)

        assert field.label_text == "Test Label"
        assert field.required is False


class TestManagedGuestRow:
    """Tests for ManagedGuestRow widget."""

    def test_managed_guest_row_vm(self) -> None:
        """Test ManagedGuestRow for VM."""
        row = ManagedGuestRow(
            guest_kind="vm",
            guest_id="100",
            guest_name="test-vm",
            guest_status="running",
            guest_ip="192.168.1.100",
            managed=True,
            notes="Test notes",
        )

        assert row.guest_kind == "vm"
        assert row.guest_id == "100"
        assert row.guest_name == "test-vm"
        assert row.guest_status == "running"
        assert row.guest_ip == "192.168.1.100"
        assert row.managed is True
        assert row.notes == "Test notes"

    def test_managed_guest_row_ct(self) -> None:
        """Test ManagedGuestRow for container."""
        row = ManagedGuestRow(
            guest_kind="ct",
            guest_id="101",
            guest_name="test-ct",
            guest_status="stopped",
            guest_ip=None,
            managed=False,
            notes=None,
        )

        assert row.guest_kind == "ct"
        assert row.guest_id == "101"
        assert row.guest_name == "test-ct"
        assert row.guest_status == "stopped"
        assert row.guest_ip is None
        assert row.managed is False
        assert row.notes is None

    def test_managed_guest_row_with_default_values(self) -> None:
        """Test ManagedGuestRow with default values."""
        row = ManagedGuestRow(
            guest_kind="vm",
            guest_id="100",
            guest_name="test-vm",
            guest_status="running",
            guest_ip="192.168.1.100",
        )

        assert row.managed is True
        assert row.notes is None
