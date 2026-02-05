"""Shared helpers for Questionary-based CLI prompts."""

from __future__ import annotations

from collections.abc import Sequence

import questionary


class WizardAbort(RuntimeError):
    """Raised when the user aborts a Questionary prompt."""


_DEF_EMPTY_KEYWORD = "none"


def _comma_join(values: Sequence[str] | None) -> str:
    if not values:
        return ""
    return ", ".join(values)


def _split_csv(value: str) -> list[str]:
    return [item.strip() for item in value.split(",") if item.strip()]


def ask_text(message: str, *, default: str | None = None, required: bool = False) -> str:
    """Prompt for a text value, optionally enforcing a non-empty response."""

    prompt_default = default or ""
    while True:
        response = questionary.text(message, default=prompt_default).ask()
        if response is None:
            raise WizardAbort()
        result = response.strip()
        if result:
            return result
        if prompt_default and not required:
            return prompt_default
        if required:
            questionary.print("Value is required.", style="bold red")
            continue
        return ""


def ask_optional_text(
    message: str,
    *,
    default: str | None = None,
    inherit_word: str | None = None,
    clear_word: str | None = None,
) -> str | None:
    """Prompt for optional text, supporting inherit/clear keywords."""

    prompt_default = default or ""
    while True:
        response = questionary.text(message, default=prompt_default).ask()
        if response is None:
            raise WizardAbort()
        result = response.strip()
        lowered = result.lower()
        if inherit_word and lowered == inherit_word:
            return None
        if clear_word and lowered == clear_word:
            return None
        if not result:
            return default
        return result


def ask_optional_path(
    message: str,
    *,
    default: str | None = None,
    clear_word: str | None = None,
) -> str | None:
    """Prompt for an optional filesystem path."""

    prompt_default = default or ""
    while True:
        response = questionary.path(message, default=prompt_default).ask()
        if response is None:
            raise WizardAbort()
        result = response.strip()
        if clear_word and result.lower() == clear_word:
            return None
        if not result:
            return default
        return result


def ask_csv_list(
    message: str,
    *,
    current: Sequence[str] | None,
    allow_inherit: bool = False,
    inherit_word: str = "inherit",
    empty_keyword: str | None = _DEF_EMPTY_KEYWORD,
    keep_current_on_blank: bool = True,
) -> list[str] | None:
    """Prompt for a comma separated list, optionally handling inherit/empty keywords."""

    current_list = list(current) if current is not None else None
    default_text = _comma_join(current_list)
    hint_parts: list[str] = ["comma separated"]
    if empty_keyword:
        hint_parts.append(f"enter '{empty_keyword}' for an empty list")
    if allow_inherit:
        hint_parts.append(f"enter '{inherit_word}' to inherit")
    hint = f" ({'; '.join(hint_parts)})" if hint_parts else ""
    prompt = f"{message}{hint}"
    while True:
        response = questionary.text(prompt, default=default_text).ask()
        if response is None:
            raise WizardAbort()
        result = response.strip()
        lowered = result.lower()
        if allow_inherit and lowered == inherit_word:
            return None
        if empty_keyword and lowered == empty_keyword:
            return []
        if not result:
            if keep_current_on_blank:
                return current_list
            return []
        return _split_csv(result)


def ask_int(
    message: str,
    *,
    default: int | None,
    required: bool,
    allow_inherit: bool = False,
    inherit_word: str = "inherit",
) -> int | None:
    """Prompt for integers with optional inherit support."""

    default_text = str(default) if default is not None else ""
    hint_parts: list[str] = []
    if allow_inherit:
        hint_parts.append(f"enter '{inherit_word}' to remove override")
    hint = f" ({'; '.join(hint_parts)})" if hint_parts else ""
    prompt = f"{message}{hint}"
    while True:
        response = questionary.text(prompt, default=default_text).ask()
        if response is None:
            raise WizardAbort()
        result = response.strip()
        lowered = result.lower()
        if allow_inherit and lowered == inherit_word:
            return None
        if not result:
            if default is not None and not required:
                return default
            if required:
                questionary.print("Value is required.", style="bold red")
                continue
            return None
        try:
            value = int(result)
        except ValueError:
            questionary.print("Please enter a valid integer.", style="bold red")
            continue
        if value <= 0 and required:
            questionary.print("Value must be greater than zero.", style="bold red")
            continue
        return value


def ask_bool(message: str, *, default: bool) -> bool:
    """Prompt for a boolean via confirmation."""

    response = questionary.confirm(message, default=default).ask()
    if response is None:
        raise WizardAbort()
    return bool(response)


def ask_optional_bool(message: str, *, current: bool | None) -> bool | None:
    """Prompt for an optional boolean supporting inherit semantics."""

    hint = "leave blank to inherit" if current is None else "enter 'inherit' to clear"
    prompt = f"{message} ({hint})"
    while True:
        response = questionary.text(prompt, default="" if current is None else str(current)).ask()
        if response is None:
            raise WizardAbort()
        result = response.strip().lower()
        if not result:
            return current
        if result == "inherit":
            return None
        if result in {"true", "t", "yes", "y"}:
            return True
        if result in {"false", "f", "no", "n"}:
            return False
        questionary.print("Enter true/false or 'inherit'.", style="bold red")


def ask_required_text(message: str, *, default: str | None = None) -> str:
    """Prompt for a required text value."""

    return ask_text(message, default=default, required=True)
