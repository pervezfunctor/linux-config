# Textual Migration Plan

This document outlines the migration from Questionary to Textual for the interactive CLI in [`proxmox_inventory_builder.py`](../proxmox_inventory_builder.py). The migration will modernize the interactive CLI experience with a rich TUI (Terminal User Interface) while maintaining backward compatibility with existing functionality.

**Target File**: [`proxmox_inventory_builder.py`](../proxmox_inventory_builder.py)
**Current Library**: Questionary 2.0.1
**Target Library**: Textual (to be added)
**Affected Helper File**: [`questionary_prompts.py`](../questionary_prompts.py)

---

## 1. Architecture Design

### 1.1 Application Structure

The Textual application will follow a multi-screen architecture with a central state management system:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                      InventoryBuilderApp                                      │
│  (Main Textual App - manages screens and global state)                       │
└──────────────────────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        ▼                     ▼                     ▼
┌─────────────────────┐   ┌─────────────────────┐   ┌─────────────────────┐
│   WelcomeScreen     │   │   HostSelectScreen  │   │  HostConfigScreen   │
│                     │   │                     │   │                     │
│ - Load manifest     │   │ - List hosts        │   │ - Form inputs       │
│ - Show options      │   │ - Add new host      │   │ - Validation        │
└─────────────────────┘   └─────────────────────┘   └─────────────────────┘
        │                     │                     │
        └─────────────────────┼─────────────────────┘
                              │
                              ▼
                    ┌─────────────────────┐
                    │  DiscoveryScreen    │
                    │                     │
                    │ - Progress bar      │
                    │ - Async SSH ops     │
                    │ - Status updates    │
                    └─────────────────────┘
                              │
                              ▼
                    ┌─────────────────────┐
                    │  GuestConfigScreen  │
                    │                     │
                    │ - Guest list        │
                    │ - Toggle managed    │
                    │ - Notes input       │
                    └─────────────────────┘
                              │
                              ▼
                    ┌─────────────────────┐
                    │   SummaryScreen     │
                    │                     │
                    │ - Show results      │
                    │ - Save manifest     │
                    │ - Exit options      │
                    └─────────────────────┘
```

### 1.2 Widget Organization

Each screen will be composed of reusable widgets:

| Widget Type | Purpose | Textual Equivalent |
|-------------|---------|-------------------|
| Text Input | Required/optional text fields | `Input` widget |
| Selection | Host selection, menu choices | `Select` widget |
| Boolean | Yes/no questions | `Checkbox` or `Switch` |
| CSV List | Comma-separated values | `Input` with validation |
| Styled Output | Notices, errors, success | `Rich` widget or `Static` |
| Progress | Async operation status | `ProgressBar` widget |
| Status Bar | Current operation state | `Footer` widget |

### 1.3 State Management Approach

State will be managed through a combination of:

1. **App-level State** (`InventoryBuilderApp`):
   - `manifest_path`: Path to the TOML manifest
   - `manifest_state`: Current `ManifestState` object
   - `selected_host`: Currently selected `HostForm`
   - `guest_discoveries`: List of discovered guests
   - `managed_guests`: List of configured guests
   - `is_new_host`: Boolean flag for new host creation

2. **Screen-level State**:
   - Each screen maintains its own transient state
   - Data flows from screen to app via callbacks

3. **Pydantic Models**:
   - Continue using existing models from [`proxmox_manifest_models.py`](../proxmox_manifest_models.py)
   - Add new models for Textual-specific state if needed

### 1.4 Async SSH Operations Integration

Textual provides built-in support for async operations through its worker system:

```python
# Pattern for running async SSH operations in Textual
from textual.worker import Worker, get_worker

class DiscoveryWorker(Worker):
    def run(self, host: HostForm, defaults: DefaultsForm) -> list[GuestDiscovery]:
        # This runs in a separate thread
        return asyncio.run(discover_inventory(host, defaults))
```

Key considerations:
- Use `Worker` for blocking SSH operations
- Use `async` methods for non-blocking UI updates
- Provide progress feedback via message passing
- Handle cancellation gracefully

---

## 2. Component Mapping

### 2.1 Questionary to Textual Widget Mapping

| Questionary Function | Current Usage | Textual Equivalent | Implementation Notes |
|---------------------|---------------|-------------------|---------------------|
| `questionary.print()` | Styled output (lines 64, 119, 125, 133, 135, 333, 341, 344, 347) | `Rich` widget or `Static` with `Rich` rendering | Use `Rich` for styled text, `Static` for simple messages |
| `questionary.select()` | Host selection (lines 137-139) | `Select` widget | Map `Choice` objects to `Select` options |
| `ask_required_text()` | Required text inputs (line 150, 151) | `Input` widget with `Validator` | Add custom validator for non-empty |
| `ask_optional_text()` | Optional text inputs (line 152, 304) | `Input` widget with default value | Handle empty input as default |
| `ask_csv_list()` | CSV list input (lines 153-159) | `Input` widget with CSV validator | Parse and validate comma-separated values |
| `ask_bool()` | Boolean questions (lines 160, 303) | `Switch` or `Checkbox` widget | `Switch` is more intuitive for yes/no |
| `WizardAbort` exception | User cancellation (lines 140, 343) | Screen dismissal or app exit | Use `app.pop_screen()` or `app.exit()` |

### 2.2 Styled Output Mapping

| Questionary Style | Textual Rich Style | Example |
|-------------------|-------------------|---------|
| `bold yellow` | `bold yellow` | `[bold yellow]Warning message[/]` |
| `bold green` | `bold green` | `[bold green]Success message[/]` |
| `bold red` | `bold red` | `[bold red]Error message[/]` |

### 2.3 Helper Function Replacements

The following helper functions from [`questionary_prompts.py`](../questionary_prompts.py) need Textual equivalents:

| Function | Purpose | Textual Implementation |
|----------|---------|------------------------|
| `ask_required_text()` | Required text input | `RequiredInput` widget |
| `ask_optional_text()` | Optional text input | `OptionalInput` widget |
| `ask_csv_list()` | CSV list input | `CSVInput` widget |
| `ask_bool()` | Boolean question | `BoolSwitch` widget |
| `ask_optional_path()` | Optional path input | `PathInput` widget |
| `ask_int()` | Integer input | `IntInput` widget |
| `ask_optional_bool()` | Optional boolean | `OptionalBoolSwitch` widget |

---

## 3. Implementation Phases

### Phase 1: Setup and Basic Textual App Structure

**Objectives**:
- Add Textual dependency to [`pyproject.toml`](../pyproject.toml)
- Create basic app structure
- Set up screen navigation
- Create placeholder screens

**Tasks**:
1. Add `textual>=0.80.0` to dependencies in [`pyproject.toml`](../pyproject.toml)
2. Run `uv lock` to update dependency lock file
3. Create new file: `proxmox_cli/textual_app.py` with basic app structure
4. Create new file: `proxmox_cli/textual_screens.py` with screen classes
5. Create new file: `proxmox_cli/textual_widgets.py` with custom widgets
6. Update [`proxmox_cli/app.py`](../proxmox_cli/app.py) to support Textual mode
7. Create basic `WelcomeScreen` with manifest loading
8. Implement screen navigation (push/pop pattern)

**Deliverables**:
- Updated [`pyproject.toml`](../pyproject.toml) and `uv.lock`
- `proxmox_cli/textual_app.py` - Main app class
- `proxmox_cli/textual_screens.py` - Screen definitions
- `proxmox_cli/textual_widgets.py` - Custom widget base
- Working screen navigation

**Success Criteria**:
- App launches without errors
- Screens can be pushed and popped
- Basic styling is applied

### Phase 2: Replace Helper Functions

**Objectives**:
- Create Textual equivalents for all questionary helper functions
- Implement validation logic
- Handle user cancellation

**Tasks**:
1. Create `RequiredInput` widget in `proxmox_cli/textual_widgets.py`
2. Create `OptionalInput` widget in `proxmox_cli/textual_widgets.py`
3. Create `CSVInput` widget in `proxmox_cli/textual_widgets.py`
4. Create `BoolSwitch` widget in `proxmox_cli/textual_widgets.py`
5. Create `PathInput` widget in `proxmox_cli/textual_widgets.py`
6. Create `IntInput` widget in `proxmox_cli/textual_widgets.py`
7. Create `OptionalBoolSwitch` widget in `proxmox_cli/textual_widgets.py`
8. Implement validators for each widget type
9. Add error message display widgets
10. Handle user cancellation (Ctrl+C, Esc)

**Deliverables**:
- Complete set of custom widgets in `proxmox_cli/textual_widgets.py`
- Widget validators
- Error handling mechanisms

**Success Criteria**:
- All widgets accept and validate input correctly
- Error messages display appropriately
- User cancellation is handled gracefully

### Phase 3: Implement Host Selection Screen

**Objectives**:
- Replace `select_host()` function with Textual screen
- Display existing hosts
- Support adding new hosts
- Handle pre-selected host from CLI

**Tasks**:
1. Create `HostSelectScreen` in `proxmox_cli/textual_screens.py`
2. Implement host list display using `DataTable` or `ListView`
3. Add "Add new host" button
4. Handle host selection event
5. Pass selected host to next screen
6. Handle CLI pre-selection (`--host` option)
7. Add "No hosts" state handling

**Deliverables**:
- `HostSelectScreen` class
- Host selection logic
- Integration with app state

**Success Criteria**:
- Existing hosts display correctly
- New host can be added
- Pre-selected host works from CLI
- Navigation to next screen works

### Phase 4: Implement Host Configuration Form

**Objectives**:
- Replace `create_host_form()` function with Textual screen
- Collect all host configuration fields
- Apply defaults from manifest
- Validate form before submission

**Tasks**:
1. Create `HostConfigScreen` in `proxmox_cli/textual_screens.py`
2. Add form fields using custom widgets:
   - Host name (required)
   - Hostname/IP (required)
   - SSH user (optional, with default)
   - Guest SSH args (CSV list)
   - Dry-run toggle
   - Max parallel (integer)
3. Implement form validation
4. Add "Save" and "Cancel" buttons
5. Apply defaults from `state.defaults`
6. Handle form submission

**Deliverables**:
- `HostConfigScreen` class
- Form validation logic
- Integration with app state

**Success Criteria**:
- All fields accept valid input
- Defaults are applied correctly
- Form validates before submission
- Host is created/updated correctly

### Phase 5: Implement Guest Configuration Workflow

**Objectives**:
- Replace `configure_guests()` function with Textual screen
- Display discovered guests
- Allow toggling managed status
- Capture notes for each guest
- Show progress during discovery

**Tasks**:
1. Create `DiscoveryScreen` in `proxmox_cli/textual_screens.py`
2. Add progress bar for SSH operations
3. Display status messages during discovery
4. Create `GuestConfigScreen` in `proxmox_cli/textual_screens.py`
5. Display guest list using `DataTable` or `ListView`
6. Add "Managed" toggle for each guest
7. Add notes input field for each guest
8. Implement "Save All" and "Cancel" buttons
9. Handle existing guest data (load from manifest)

**Deliverables**:
- `DiscoveryScreen` class
- `GuestConfigScreen` class
- Guest configuration logic
- Integration with async discovery

**Success Criteria**:
- Discovery shows progress
- Guests display with current status
- Managed status can be toggled
- Notes can be added
- Configuration saves correctly

### Phase 6: Integrate with Existing Async Operations

**Objectives**:
- Integrate Textual app with existing async SSH operations
- Handle worker threads for blocking operations
- Provide progress feedback
- Handle errors and cancellation

**Tasks**:
1. Create `DiscoveryWorker` class for async operations
2. Integrate `discover_inventory()` with Textual worker
3. Add progress bar updates during discovery
4. Handle SSH errors in worker
5. Implement cancellation support
6. Update `run_inventory()` to use Textual app
7. Maintain backward compatibility with CLI mode

**Deliverables**:
- Worker classes for async operations
- Progress feedback mechanisms
- Error handling in worker context
- Updated `run_inventory()` function

**Success Criteria**:
- Async operations run without blocking UI
- Progress updates display correctly
- Errors are caught and displayed
- Cancellation works properly

### Phase 7: Testing and Refinement

**Objectives**:
- Write comprehensive tests
- Fix bugs and edge cases
- Optimize performance
- Update documentation

**Tasks**:
1. Create `tests/test_textual_app.py` for app tests
2. Create `tests/test_textual_widgets.py` for widget tests
3. Create `tests/test_textual_screens.py` for screen tests
4. Add integration tests for full workflow
5. Test with various manifest configurations
6. Test error scenarios (SSH failures, invalid input)
7. Test cancellation at various points
8. Update [`README.md`](../README.md) with Textual usage
9. Update [`AGENTS.md`](../AGENTS.md) with new patterns
10. Run linting and type checking

**Deliverables**:
- Comprehensive test suite
- Updated documentation
- Bug fixes
- Performance optimizations

**Success Criteria**:
- All tests pass
- Linting passes
- Type checking passes
- Documentation is complete
- User experience is smooth

---

## 4. Technical Considerations

### 4.1 Async/Await Integration with Textual

Textual is built on asyncio and provides several patterns for integrating async operations:

**Pattern 1: Worker Threads for Blocking Operations**

```python
from textual.worker import Worker, get_worker

class DiscoveryWorker(Worker):
    def run(self, host: HostForm, defaults: DefaultsForm) -> list[GuestDiscovery]:
        # This runs in a separate thread
        return asyncio.run(discover_inventory(host, defaults))

# In screen:
def on_worker_state_changed(self, event: Worker.StateChanged) -> None:
    if event.worker.is_finished:
        discoveries = event.worker.result
        self.app.guest_discoveries = discoveries
        self.push_screen("guest_config")
```

**Pattern 2: Async Methods for Non-Blocking Operations**

```python
class DiscoveryScreen(Screen):
    async def on_mount(self) -> None:
        self.progress = ProgressBar()
        await self.view.dock(self.progress)

    async def start_discovery(self) -> None:
        discoveries = await discover_inventory(
            self.app.selected_host,
            self.app.manifest_state.defaults
        )
        self.app.guest_discoveries = discoveries
```

**Pattern 3: Message Passing for Progress Updates**

```python
class DiscoveryWorker(Worker):
    def run(self, host: HostForm, defaults: DefaultsForm) -> list[GuestDiscovery]:
        self.post_message(DiscoveryProgress(0, "Starting..."))
        # discovery logic ...
        self.post_message(DiscoveryProgress(50, "Fetching VMs..."))
        # more logic ...
        return discoveries

class DiscoveryScreen(Screen):
    def on_discovery_progress(self, event: DiscoveryProgress) -> None:
        self.progress.advance(event.progress)
        self.status.update(event.message)
```

### 4.2 State Management Between Screens

Textual provides several options for state management:

**Option 1: App-Level State (Recommended)**

```python
class InventoryBuilderApp(App):
    CSS = """
    Screen {
        background: $surface;
    }
    """

    def __init__(self, options: InventoryRunOptions):
        super().__init__()
        self.options = options
        self.manifest_path = options.manifest
        self.manifest_state: ManifestState | None = None
        self.selected_host: HostForm | None = None
        self.guest_discoveries: list[GuestDiscovery] = []
        self.managed_guests: list[ManagedGuest] = []
        self.is_new_host: bool = False
```

**Option 2: Screen Parameters**

```python
# Pass data when pushing screens
self.push_screen(
    HostConfigScreen(
        defaults=self.manifest_state.defaults,
        is_new_host=True
    )
)

# Receive in screen
class HostConfigScreen(Screen):
    def __init__(self, defaults: DefaultsForm, is_new_host: bool):
        super().__init__()
        self.defaults = defaults
        self.is_new_host = is_new_host
```

**Option 3: Global State Store**

```python
class StateStore:
    _instance: ClassVar[StateStore | None] = None

    def __new__(cls) -> StateStore:
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance

    manifest_state: ManifestState | None = None
    selected_host: HostForm | None = None
```

### 4.3 Error Handling and User Cancellation

**Error Handling Pattern**

```python
class DiscoveryScreen(Screen):
    def on_worker_error(self, event: Worker.Error) -> None:
        error = event.error
        if isinstance(error, ProxmoxCLIError):
            self.notify(
                severity="error",
                title="SSH Error",
                message=f"Failed to connect: {error}"
            )
        elif isinstance(error, InventoryError):
            self.notify(
                severity="error",
                title="Inventory Error",
                message=str(error)
            )
        else:
            self.notify(
                severity="error",
                title="Unexpected Error",
                message=str(error)
            )
```

**User Cancellation Pattern**

```python
class HostConfigScreen(Screen):
    def on_key(self, event: events.Key) -> None:
        if event.key == "escape":
            self.app.pop_screen()
            return

        if event.key == "c" and event.ctrl:
            # Confirm before exiting
            self.push_screen(ConfirmExitScreen())
```

### 4.4 Backward Compatibility with Existing Code

To maintain backward compatibility:

1. **Keep Questionary Implementation**: Don't remove existing questionary code immediately
2. **Add Feature Flag**: Use environment variable or CLI flag to choose UI mode
3. **Gradual Migration**: Migrate one screen at a time
4. **Shared Business Logic**: Keep business logic in separate functions

```python
# In proxmox_inventory_builder.py
def run_inventory(options: InventoryRunOptions) -> int:
    use_textual = os.getenv("PROXMOX_USE_TEXTUAL", "false").lower() == "true"

    if use_textual:
        from proxmox_cli.textual_app import InventoryBuilderApp
        app = InventoryBuilderApp(options)
        return app.run()
    else:
        # Existing questionary implementation
        return _run_inventory_questionary(options)
```

### 4.5 Integration with Typer CLI

The Textual app will integrate with the existing Typer CLI:

```python
# In proxmox_cli/app.py
@inventory_app.command("configure")
def inventory_configure(
    manifest: Annotated[str | None, Option("--manifest", "-m", help="Manifest path")] = None,
    host: Annotated[str | None, Option("--host", help="Pre-select host")] = None,
    verbose: Annotated[bool, Option("--verbose", help="Verbose logging")] = False,
    textual: Annotated[bool, Option("--textual", "-t", help="Use Textual TUI")] = False,
) -> None:
    options = InventoryOptions(
        manifest=_manifest_path(manifest),
        host=host,
        verbose=verbose,
        textual=textual,
    )

    if textual:
        from proxmox_cli.textual_app import InventoryBuilderApp
        app = InventoryBuilderApp(options)
        exit_code = app.run()
    else:
        run_options = proxmox_inventory_builder.InventoryRunOptions(
            manifest=options.manifest,
            host=options.host,
            verbose=options.verbose,
        )
        exit_code = proxmox_inventory_builder.run_inventory(run_options)

    raise typer.Exit(code=exit_code)
```

---

## 5. File Structure Changes

### 5.1 New Files to Create

```
py/
├── proxmox_cli/
│   ├── __init__.py              # (existing)
│   ├── app.py                   # (existing - will be modified)
│   ├── models.py                # (existing - will be modified)
│   ├── textual_app.py           # (NEW) Main Textual app class
│   ├── textual_screens.py       # (NEW) All screen definitions
│   ├── textual_widgets.py       # (NEW) Custom widgets
│   └── textual_workers.py       # (NEW) Worker classes for async ops
├── tests/
│   ├── test_textual_app.py      # (NEW) App tests
│   ├── test_textual_widgets.py  # (NEW) Widget tests
│   └── test_textual_screens.py  # (NEW) Screen tests
└── plans/
    └── textual-migration-plan.md # (NEW) This document
```

### 5.2 Existing Files to Modify

| File | Modifications |
|------|---------------|
| [`pyproject.toml`](../pyproject.toml) | Add `textual>=0.80.0` to dependencies |
| `uv.lock` | Regenerate with `uv lock` |
| [`proxmox_cli/app.py`](../proxmox_cli/app.py) | Add `--textual` flag to inventory configure command |
| [`proxmox_cli/models.py`](../proxmox_cli/models.py) | Add `textual: bool` to `InventoryOptions` |
| [`proxmox_inventory_builder.py`](../proxmox_inventory_builder.py) | Keep for backward compatibility, add Textual integration |
| [`questionary_prompts.py`](../questionary_prompts.py) | Keep for backward compatibility |
| [`README.md`](../README.md) | Document Textual usage |
| [`AGENTS.md`](../AGENTS.md) | Add Textual patterns for agents |

### 5.3 Files to Keep Unchanged

The following files should remain unchanged as they contain business logic:

- [`proxmox_batch.py`](../proxmox_batch.py)
- [`proxmox_maintenance.py`](../proxmox_maintenance.py)
- [`proxmox_manifest.py`](../proxmox_manifest.py)
- [`proxmox_manifest_models.py`](../proxmox_manifest_models.py)
- [`remote_maintenance.py`](../remote_maintenance.py)
- [`logging_utils.py`](../logging_utils.py)

---

## 6. Potential Challenges and Mitigation Strategies

### 6.1 Async/Await Integration with Textual

**Challenge**: The existing code uses `asyncio.run()` for SSH operations, which may conflict with Textual's event loop.

**Mitigation**:
- Use Textual's `Worker` class for blocking operations
- Ensure all async operations are properly awaited
- Test with various SSH connection scenarios
- Implement proper cancellation handling

**Code Example**:
```python
class DiscoveryWorker(Worker):
    def run(self, host: HostForm, defaults: DefaultsForm) -> list[GuestDiscovery]:
        # Create new event loop for this thread
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        try:
            return loop.run_until_complete(discover_inventory(host, defaults))
        finally:
            loop.close()
```

### 6.2 Maintaining the Same User Experience

**Challenge**: Textual provides a different UX than Questionary. Users may be confused by the change.

**Mitigation**:
- Keep the same workflow and questions
- Use similar terminology and labels
- Provide clear navigation instructions
- Add a "help" section explaining the new UI
- Consider a "classic mode" flag to use Questionary

**Code Example**:
```python
class HostConfigScreen(Screen):
    BINDINGS = [
        ("ctrl+s", "save", "Save"),
        ("ctrl+c", "cancel", "Cancel"),
        ("f1", "help", "Help"),
    ]

    def action_help(self) -> None:
        self.push_screen(HelpScreen())
```

### 6.3 Testing Approach

**Challenge**: Testing TUI applications is more complex than testing CLI applications.

**Mitigation**:
- Use Textual's `AppTest` context manager for unit tests
- Mock SSH operations for integration tests
- Test widget validation independently
- Test screen navigation logic
- Use pytest-asyncio for async tests

**Code Example**:
```python
from textual.app import AppTest

def test_host_config_screen_validation():
    app = InventoryBuilderApp(InventoryRunOptions(...))
    async with AppTest(app).run_test() as pilot:
        await pilot.click("#host-name-input")
        await pilot.press("ctrl+v")  # Paste
        await pilot.press("enter")

        # Check validation error
        assert app.query_one("#error-message").text == "Host name is required"
```

### 6.4 Performance with Large Guest Lists

**Challenge**: Discovering and displaying many guests could be slow.

**Mitigation**:
- Use virtual scrolling for large lists
- Implement lazy loading for guest details
- Show progress during discovery
- Cache discovered guests
- Allow filtering/searching

**Code Example**:
```python
class GuestList(DataSource):
    def __init__(self, guests: list[GuestDiscovery]):
        self.guests = guests
        self.filtered = guests

    async def get_item_at_index(self, index: int) -> GuestDiscovery:
        return self.filtered[index]

    async def get_item_count(self) -> int:
        return len(self.filtered)

    def filter(self, query: str) -> None:
        if not query:
            self.filtered = self.guests
        else:
            self.filtered = [
                g for g in self.guests
                if query.lower() in g.name.lower()
            ]
```

### 6.5 Error Recovery

**Challenge**: SSH errors or invalid input should not crash the app.

**Mitigation**:
- Wrap all SSH operations in try/except
- Provide clear error messages
- Allow retry or skip options
- Maintain partial state on errors
- Log errors for debugging

**Code Example**:
```python
class DiscoveryScreen(Screen):
    def on_worker_error(self, event: Worker.Error) -> None:
        error = event.error

        if isinstance(error, ProxmoxCLIError):
            self.notify(
                severity="error",
                title="Connection Failed",
                message=f"Could not connect to host: {error}",
                timeout=10
            )
            self.push_screen(RetryScreen(
                message="Retry SSH connection?",
                on_retry=self.retry_discovery,
                on_skip=self.skip_discovery
            ))
```

### 6.6 Terminal Compatibility

**Challenge**: Textual requires certain terminal capabilities that may not be available on all systems.

**Mitigation**:
- Detect terminal capabilities on startup
- Fall back to Questionary if Textual is not supported
- Provide clear error messages
- Document terminal requirements

**Code Example**:
```python
def check_terminal_compatibility() -> bool:
    import shutil
    import sys

    # Check terminal size
    cols, rows = shutil.get_terminal_size()
    if cols < 80 or rows < 24:
        return False

    # Check if running in a TTY
    if not sys.stdout.isatty():
        return False

    # Check for color support
    if "TERM" not in os.environ:
        return False

    return True
```

---

## 7. Code Examples

### 7.1 Main App Structure

```python
"""Textual TUI application for Proxmox inventory builder."""

from __future__ import annotations

from pathlib import Path
from typing import cast

from textual.app import App, ComposeResult
from textual.containers import Container, Horizontal, Vertical
from textual.widgets import Button, Footer, Header, Static

from proxmox_cli.models import InventoryOptions
from proxmox_cli.textual_screens import (
    DiscoveryScreen,
    GuestConfigScreen,
    HostConfigScreen,
    HostSelectScreen,
    WelcomeScreen,
)
from proxmox_manifest import load_manifest_state
from proxmox_manifest_models import DefaultsForm, HostForm, ManifestState


class InventoryBuilderApp(App):
    """Main Textual application for Proxmox inventory building."""

    CSS = """
    Screen {
        background: $surface;
    }

    .title {
        text-align: center;
        text-style: bold;
        color: $accent;
        padding: 1;
    }

    .notice {
        text-style: italic;
        color: $warning;
        padding: 1;
        text-align: center;
    }

    .error {
        text-style: bold;
        color: $error;
        padding: 1;
    }

    .success {
        text-style: bold;
        color: $success;
        padding: 1;
    }

    Button {
        margin: 1;
    }

    #container {
        padding: 2;
    }
    """

    BINDINGS = [
        ("ctrl+q", "quit", "Quit"),
        ("f1", "help", "Help"),
    ]

    def __init__(self, options: InventoryOptions):
        super().__init__()
        self.options = options
        self.manifest_path = options.manifest
        self.manifest_state: ManifestState | None = None
        self.selected_host: HostForm | None = None
        self.guest_discoveries: list[GuestDiscovery] = []
        self.managed_guests: list[ManagedGuest] = []
        self.is_new_host: bool = False
        self._load_manifest()

    def _load_manifest(self) -> None:
        """Load the manifest file."""
        if self.manifest_path.exists():
            self.manifest_state = load_manifest_state(self.manifest_path)
        else:
            self.manifest_state = ManifestState.empty()

    def compose(self) -> ComposeResult:
        """Compose the initial UI."""
        yield Header()
        yield Container(
            Vertical(
                Static("Proxmox Inventory Builder", classes="title"),
                Static("Loading manifest...", id="status"),
                id="container",
            )
        )
        yield Footer()

    def on_mount(self) -> None:
        """Called when the app is mounted."""
        self.push_screen(WelcomeScreen(self.manifest_path))

    def action_help(self) -> None:
        """Show help screen."""
        from proxmox_cli.textual_screens import HelpScreen
        self.push_screen(HelpScreen())

    def navigate_to_host_select(self) -> None:
        """Navigate to host selection screen."""
        self.push_screen(HostSelectScreen(
            hosts=self.manifest_state.hosts if self.manifest_state else [],
            defaults=self.manifest_state.defaults if self.manifest_state else DefaultsForm(),
            preselected_host=self.options.host,
        ))

    def navigate_to_host_config(self, is_new: bool = False) -> None:
        """Navigate to host configuration screen."""
        self.is_new_host = is_new
        self.push_screen(HostConfigScreen(
            defaults=self.manifest_state.defaults if self.manifest_state else DefaultsForm(),
            existing_host=self.selected_host if not is_new else None,
        ))

    def navigate_to_discovery(self) -> None:
        """Navigate to discovery screen."""
        if not self.selected_host:
            self.notify(
                severity="error",
                title="No Host Selected",
                message="Please select a host first."
            )
            return

        self.push_screen(DiscoveryScreen(
            host=self.selected_host,
            defaults=self.manifest_state.defaults if self.manifest_state else DefaultsForm(),
        ))

    def navigate_to_guest_config(self) -> None:
        """Navigate to guest configuration screen."""
        if not self.guest_discoveries:
            self.notify(
                severity="warning",
                title="No Guests Discovered",
                message="No guests were found on this host."
            )
            return

        self.push_screen(GuestConfigScreen(
            host=self.selected_host,
            discoveries=self.guest_discoveries,
        ))

    def save_manifest(self) -> None:
        """Save the manifest to disk."""
        from proxmox_manifest import write_manifest

        if not self.manifest_state:
            self.notify(
                severity="error",
                title="No Manifest",
                message="No manifest to save."
            )
            return

        write_manifest(self.manifest_state, self.manifest_path)
        self.notify(
            severity="success",
            title="Saved",
            message=f"Manifest saved to {self.manifest_path}"
        )
```

### 7.2 Custom Widget Example

```python
"""Custom Textual widgets for Proxmox inventory builder."""

from __future__ import annotations

from typing import Any

from pydantic import ValidationError
from textual.containers import Horizontal, Vertical
from textual.message import Message
from textual.widgets import Input, Label, Static


class InputChanged(Message):
    """Emitted when an input value changes."""

    def __init__(self, value: str) -> None:
        self.value = value
        super().__init__()


class RequiredInput(Vertical):
    """A text input that requires a non-empty value."""

    def __init__(
        self,
        label: str,
        placeholder: str = "",
        default: str = "",
        **kwargs: Any,
    ) -> None:
        super().__init__(**kwargs)
        self.label_text = label
        self.placeholder = placeholder
        self.default = default
        self._value = default

    def compose(self) -> ComposeResult:
        """Compose the widget."""
        yield Label(self.label_text)
        yield Input(
            placeholder=self.placeholder,
            value=self.default,
            id="input"
        )
        yield Static("", id="error")

    def on_input_changed(self, event: Input.Changed) -> None:
        """Handle input changes."""
        self._value = event.value
        error = self.query_one("#error", Static)

        if not event.value.strip():
            error.update("This field is required")
            error.add_class("error")
        else:
            error.update("")
            error.remove_class("error")

        self.post_message(InputChanged(event.value))

    @property
    def value(self) -> str:
        """Get the input value."""
        return self._value

    def is_valid(self) -> bool:
        """Check if the input is valid."""
        return bool(self._value.strip())


class OptionalInput(Vertical):
    """A text input that allows empty values."""

    def __init__(
        self,
        label: str,
        placeholder: str = "",
        default: str = "",
        **kwargs: Any,
    ) -> None:
        super().__init__(**kwargs)
        self.label_text = label
        self.placeholder = placeholder
        self.default = default
        self._value = default

    def compose(self) -> ComposeResult:
        """Compose the widget."""
        yield Label(f"{self.label_text} (optional)")
        yield Input(
            placeholder=self.placeholder,
            value=self.default,
            id="input"
        )

    def on_input_changed(self, event: Input.Changed) -> None:
        """Handle input changes."""
        self._value = event.value
        self.post_message(InputChanged(event.value))

    @property
    def value(self) -> str:
        """Get the input value."""
        return self._value


class CSVInput(Vertical):
    """A text input for comma-separated values."""

    def __init__(
        self,
        label: str,
        placeholder: str = "",
        default: list[str] | None = None,
        **kwargs: Any,
    ) -> None:
        super().__init__(**kwargs)
        self.label_text = label
        self.placeholder = placeholder
        self.default = ", ".join(default or [])
        self._value: list[str] = default or []

    def compose(self) -> ComposeResult:
        """Compose the widget."""
        yield Label(f"{self.label_text} (comma-separated)")
        yield Input(
            placeholder=self.placeholder,
            value=self.default,
            id="input"
        )
        yield Static("", id="error")

    def on_input_changed(self, event: Input.Changed) -> None:
        """Handle input changes."""
        error = self.query_one("#error", Static)

        if not event.value.strip():
            self._value = []
            error.update("")
            error.remove_class("error")
        else:
            try:
                self._value = [item.strip() for item in event.value.split(",") if item.strip()]
                error.update("")
                error.remove_class("error")
            except Exception:
                error.update("Invalid CSV format")
                error.add_class("error")

        self.post_message(InputChanged(event.value))

    @property
    def value(self) -> list[str]:
        """Get the input value as a list."""
        return self._value

    def is_valid(self) -> bool:
        """Check if the input is valid."""
        return not self.query_one("#error", Static).text


class BoolSwitch(Vertical):
    """A boolean switch widget."""

    def __init__(
        self,
        label: str,
        default: bool = False,
        **kwargs: Any,
    ) -> None:
        super().__init__(**kwargs)
        self.label_text = label
        self.default = default
        self._value = default

    def compose(self) -> ComposeResult:
        """Compose the widget."""
        from textual.widgets import Switch
        yield Label(self.label_text)
        yield Switch(value=self.default, id="switch")

    def on_switch_changed(self, event: Switch.Changed) -> None:
        """Handle switch changes."""
        self._value = event.value

    @property
    def value(self) -> bool:
        """Get the switch value."""
        return self._value
```

### 7.3 Screen Example

```python
"""Textual screens for Proxmox inventory builder."""

from __future__ import annotations

from typing import Any

from pydantic import ValidationError
from textual.containers import Horizontal, Vertical
from textual.screen import Screen
from textual.widgets import Button, DataTable, Footer, Header, Static

from proxmox_cli.textual_widgets import (
    BoolSwitch,
    CSVInput,
    OptionalInput,
    RequiredInput,
)
from proxmox_manifest_models import DefaultsForm, HostForm


class HostConfigScreen(Screen):
    """Screen for configuring a host entry."""

    CSS = """
    HostConfigScreen {
        align: center middle;
    }

    #form-container {
        width: 60;
        max-width: 80;
        border: thick $primary;
        padding: 2;
    }

    .error {
        color: $error;
        text-style: bold;
    }
    """

    BINDINGS = [
        ("ctrl+s", "save", "Save"),
        ("escape", "cancel", "Cancel"),
    ]

    def __init__(
        self,
        defaults: DefaultsForm,
        existing_host: HostForm | None = None,
        **kwargs: Any,
    ) -> None:
        super().__init__(**kwargs)
        self.defaults = defaults
        self.existing_host = existing_host
        self.is_new = existing_host is None

    def compose(self) -> Any:
        """Compose the screen."""
        yield Header()
        yield Vertical(
            Static(
                f"{'Add' if self.is_new else 'Edit'} Host Entry",
                classes="title"
            ),
            Vertical(
                RequiredInput(
                    label="Host Entry Name",
                    placeholder="e.g., prod-server-1",
                    default=self.existing_host.name if self.existing_host else "",
                    id="host-name"
                ),
                RequiredInput(
                    label="Proxmox Hostname or IP",
                    placeholder="e.g., proxmox.example.com",
                    default=self.existing_host.host if self.existing_host else "",
                    id="host-address"
                ),
                OptionalInput(
                    label="SSH User",
                    placeholder="e.g., root",
                    default=self.existing_host.user if self.existing_host else self.defaults.user or "",
                    id="ssh-user"
                ),
                CSVInput(
                    label="Additional SSH Args for Guests",
                    placeholder="e.g., -o StrictHostKeyChecking=no",
                    default=self.existing_host.guest_ssh_extra_args if self.existing_host else self.defaults.guest_ssh_extra_args,
                    id="guest-ssh-args"
                ),
                BoolSwitch(
                    label="Enable Dry-Run by Default",
                    default=self.existing_host.dry_run if self.existing_host else self.defaults.dry_run,
                    id="dry-run"
                ),
                OptionalInput(
                    label="Max Parallel Guest Actions",
                    placeholder="e.g., 2",
                    default=str(self.existing_host.max_parallel if self.existing_host else self.defaults.max_parallel),
                    id="max-parallel"
                ),
                Horizontal(
                    Button("Save", variant="primary", id="save-btn"),
                    Button("Cancel", variant="default", id="cancel-btn"),
                ),
                id="form-container",
            ),
        )
        yield Footer()

    def on_button_pressed(self, event: Button.Pressed) -> None:
        """Handle button presses."""
        if event.button.id == "save-btn":
            self.action_save()
        elif event.button.id == "cancel-btn":
            self.action_cancel()

    def action_save(self) -> None:
        """Save the host configuration."""
        # Get values from widgets
        host_name = self.query_one("#host-name", RequiredInput).value
        host_address = self.query_one("#host-address", RequiredInput).value
        ssh_user = self.query_one("#ssh-user", OptionalInput).value
        guest_ssh_args = self.query_one("#guest-ssh-args", CSVInput).value
        dry_run = self.query_one("#dry-run", BoolSwitch).value
        max_parallel_str = self.query_one("#max-parallel", OptionalInput).value

        # Validate required fields
        if not self.query_one("#host-name", RequiredInput).is_valid():
            self.notify(
                severity="error",
                title="Validation Error",
                message="Host name is required."
            )
            return

        if not self.query_one("#host-address", RequiredInput).is_valid():
            self.notify(
                severity="error",
                title="Validation Error",
                message="Host address is required."
            )
            return

        # Parse max_parallel
        try:
            max_parallel = int(max_parallel_str) if max_parallel_str else self.defaults.max_parallel
        except ValueError:
            self.notify(
                severity="error",
                title="Validation Error",
                message="Max parallel must be a valid integer."
            )
            return

        # Create or update host
        host_form = HostForm(
            name=host_name,
            host=host_address,
            user=ssh_user or None,
            guest_ssh_extra_args=guest_ssh_args or None,
            max_parallel=max_parallel,
            dry_run=dry_run,
        )

        # Update app state
        app = self.app
        app.selected_host = host_form

        if self.is_new:
            if app.manifest_state:
                app.manifest_state.hosts.append(host_form)

        self.notify(
            severity="success",
            title="Saved",
            message=f"Host '{host_name}' saved successfully."
        )

        # Navigate to next screen
        self.app.pop_screen()
        self.app.navigate_to_discovery()

    def action_cancel(self) -> None:
        """Cancel the operation."""
        self.app.pop_screen()
```

### 7.4 Worker Example

```python
"""Worker classes for async operations in Textual."""

from __future__ import annotations

import asyncio

from textual.worker import Worker, get_worker

from proxmox_inventory_builder import discover_inventory
from proxmox_manifest_models import DefaultsForm, HostForm


class DiscoveryWorker(Worker):
    """Worker for discovering guests on a Proxmox host."""

    def __init__(
        self,
        host: HostForm,
        defaults: DefaultsForm,
        **kwargs: Any,
    ) -> None:
        super().__init__(**kwargs)
        self.host = host
        self.defaults = defaults

    def run(self) -> list[GuestDiscovery]:
        """Run the discovery process in a worker thread."""
        # Create a new event loop for this thread
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)

        try:
            # Run the async discovery
            discoveries = loop.run_until_complete(
                discover_inventory(self.host, self.defaults)
            )
            return discoveries
        finally:
            loop.close()
```

### 7.5 Discovery Screen Example

```python
"""Discovery screen with progress tracking."""

from __future__ import annotations

from typing import Any

from textual.containers import Vertical
from textual.screen import Screen
from textual.widgets import Button, Footer, Header, ProgressBar, Static

from proxmox_cli.textual_workers import DiscoveryWorker
from proxmox_manifest_models import DefaultsForm, HostForm


class DiscoveryScreen(Screen):
    """Screen for discovering guests on a host."""

    CSS = """
    DiscoveryScreen {
        align: center middle;
    }

    #progress-container {
        width: 60;
        max-width: 80;
        border: thick $primary;
        padding: 2;
    }
    """

    BINDINGS = [
        ("escape", "cancel", "Cancel"),
    ]

    def __init__(
        self,
        host: HostForm,
        defaults: DefaultsForm,
        **kwargs: Any,
    ) -> None:
        super().__init__(**kwargs)
        self.host = host
        self.defaults = defaults

    def compose(self) -> Any:
        """Compose the screen."""
        yield Header()
        yield Vertical(
            Static(
                f"Discovering guests on {self.host.name}...",
                classes="title"
            ),
            Static("Connecting to host...", id="status"),
            ProgressBar(
                total=100,
                show_eta=False,
                id="progress"
            ),
            Button("Cancel", variant="default", id="cancel-btn"),
            id="progress-container",
        )
        yield Footer()

    def on_mount(self) -> None:
        """Called when the screen is mounted."""
        # Start the discovery worker
        self.run_worker(
            DiscoveryWorker(self.host, self.defaults),
            exclusive=True,
        )

    def on_worker_state_changed(self, event: Worker.StateChanged) -> None:
        """Handle worker state changes."""
        status = self.query_one("#status", Static)
        progress = self.query_one("#progress", ProgressBar)

        if event.worker.is_running:
            status.update("Discovering guests...")
            progress.advance(10)

        elif event.worker.is_finished:
            progress.advance(100)
            status.update("Discovery complete!")

            # Get the results
            discoveries = event.worker.result
            self.app.guest_discoveries = discoveries

            # Navigate to guest config
            self.notify(
                severity="success",
                title="Discovery Complete",
                message=f"Found {len(discoveries)} guests."
            )
            self.app.pop_screen()
            self.app.navigate_to_guest_config()

        elif event.worker.is_cancelled:
            status.update("Discovery cancelled.")
            self.app.pop_screen()

    def on_worker_error(self, event: Worker.Error) -> None:
        """Handle worker errors."""
        status = self.query_one("#status", Static)

        error = event.error
        status.update(f"Error: {error}")

        self.notify(
            severity="error",
            title="Discovery Failed",
            message=str(error),
        )

    def on_button_pressed(self, event: Button.Pressed) -> None:
        """Handle button presses."""
        if event.button.id == "cancel-btn":
            self.action_cancel()

    def action_cancel(self) -> None:
        """Cancel the discovery."""
        # Cancel the worker
        for worker in self.workers:
            if isinstance(worker, DiscoveryWorker):
                worker.cancel()
                break
```

---

## 8. Testing Strategy

### 8.1 Unit Tests

Test individual widgets and screens in isolation:

```python
"""Tests for Textual widgets."""

import pytest
from textual.app import AppTest
from textual.widgets import Input

from proxmox_cli.textual_widgets import RequiredInput, OptionalInput, CSVInput, BoolSwitch


def test_required_input_validation():
    """Test that RequiredInput validates non-empty values."""
    app = AppTest()

    async with app.run_test() as pilot:
        # Add the widget
        await pilot.pause()
        widget = RequiredInput(label="Test Label")
        await app.mount(widget)

        # Test empty input
        input_widget = widget.query_one(Input)
        input_widget.value = ""
        assert not widget.is_valid()

        # Test valid input
        input_widget.value = "test-value"
        assert widget.is_valid()


def test_csv_input_parsing():
    """Test that CSVInput correctly parses comma-separated values."""
    app = AppTest()

    async with app.run_test() as pilot:
        await pilot.pause()
        widget = CSVInput(label="Test Label")
        await app.mount(widget)

        # Test CSV parsing
        input_widget = widget.query_one(Input)
        input_widget.value = "arg1, arg2, arg3"
        assert widget.value == ["arg1", "arg2", "arg3"]

        # Test empty input
        input_widget.value = ""
        assert widget.value == []


def test_bool_switch():
    """Test that BoolSwitch correctly tracks boolean state."""
    app = AppTest()

    async with app.run_test() as pilot:
        await pilot.pause()
        widget = BoolSwitch(label="Test Label", default=False)
        await app.mount(widget)

        # Test default value
        assert widget.value is False

        # Test toggle
        from textual.widgets import Switch
        switch = widget.query_one(Switch)
        switch.value = True
        assert widget.value is True
```

### 8.2 Integration Tests

Test the full workflow:

```python
"""Integration tests for Textual app."""

import pytest
from pathlib import Path
from textual.app import AppTest

from proxmox_cli.textual_app import InventoryBuilderApp
from proxmox_cli.models import InventoryOptions


@pytest.fixture
def temp_manifest(tmp_path: Path) -> Path:
    """Create a temporary manifest file."""
    manifest = tmp_path / "proxmox-hosts.toml"
    manifest.write_text("""
[defaults]
user = "root"

[[hosts]]
name = "test-host"
host = "test.example.com"
""")
    return manifest


def test_full_workflow(temp_manifest: Path):
    """Test the full workflow from manifest load to guest config."""
    options = InventoryOptions(
        manifest=temp_manifest,
        host=None,
        verbose=False,
        textual=True,
    )

    app = InventoryBuilderApp(options)

    async with AppTest(app).run_test() as pilot:
        # Test welcome screen
        assert len(app.query("WelcomeScreen")) == 1

        # Navigate to host select
        app.navigate_to_host_select()
        await pilot.pause()

        # Test host select screen
        assert len(app.query("HostSelectScreen")) == 1

        # Select existing host
        # ... (continue testing workflow)
```

### 8.3 Mock Tests

Test with mocked SSH operations:

```python
"""Tests with mocked SSH operations."""

import pytest
from unittest.mock import AsyncMock, patch
from pathlib import Path

from proxmox_cli.textual_app import InventoryBuilderApp
from proxmox_cli.models import InventoryOptions
from proxmox_inventory_builder import GuestDiscovery


@pytest.mark.asyncio
async def test_discovery_with_mock_ssh(tmp_path: Path):
    """Test discovery with mocked SSH operations."""
    # Create mock discoveries
    mock_discoveries = [
        GuestDiscovery(
            kind="vm",
            identifier="100",
            name="test-vm",
            status="running",
            ip="192.168.1.100",
        )
    ]

    # Mock the discover_inventory function
    with patch("proxmox_cli.textual_screens.discover_inventory", new_callable=AsyncMock) as mock_discover:
        mock_discover.return_value = mock_discoveries

        # Create app and run discovery
        manifest = tmp_path / "proxmox-hosts.toml"
        options = InventoryOptions(manifest=manifest, host=None, verbose=False, textual=True)
        app = InventoryBuilderApp(options)

        # ... (run discovery and verify results)

        mock_discover.assert_called_once()
```

---

## 9. Rollout Plan

### 9.1 Phased Rollout

1. **Phase 1 (Week 1)**: Setup and basic structure
   - Add Textual dependency
   - Create basic app structure
   - Implement placeholder screens

2. **Phase 2 (Week 2)**: Widget development
   - Implement all custom widgets
   - Add validators
   - Write widget tests

3. **Phase 3 (Week 3)**: Screen implementation
   - Implement HostSelectScreen
   - Implement HostConfigScreen
   - Write screen tests

4. **Phase 4 (Week 4)**: Discovery and guest config
   - Implement DiscoveryScreen
   - Implement GuestConfigScreen
   - Integrate async operations

5. **Phase 5 (Week 5)**: Integration and testing
   - Integrate with CLI
   - Write integration tests
   - Fix bugs

6. **Phase 6 (Week 6)**: Documentation and polish
   - Update documentation
   - Add help screens
   - Performance optimization

### 9.2 Feature Flag Strategy

Use a feature flag to control Textual vs Questionary:

```python
# In proxmox_cli/app.py
@inventory_app.command("configure")
def inventory_configure(
    manifest: Annotated[str | None, Option("--manifest", "-m", help="Manifest path")] = None,
    host: Annotated[str | None, Option("--host", help="Pre-select host")] = None,
    verbose: Annotated[bool, Option("--verbose", help="Verbose logging")] = False,
    textual: Annotated[bool, Option("--textual", "-t", help="Use Textual TUI")] = False,
) -> None:
    options = InventoryOptions(
        manifest=_manifest_path(manifest),
        host=host,
        verbose=verbose,
        textual=textual,
    )

    if textual:
        from proxmox_cli.textual_app import InventoryBuilderApp
        app = InventoryBuilderApp(options)
        exit_code = app.run()
    else:
        # Use existing questionary implementation
        run_options = proxmox_inventory_builder.InventoryRunOptions(
            manifest=options.manifest,
            host=options.host,
            verbose=options.verbose,
        )
        exit_code = proxmox_inventory_builder.run_inventory(run_options)

    raise typer.Exit(code=exit_code)
```

### 9.3 Migration Path

1. **Initial Release**: Textual available via `--textual` flag
2. **Beta Period**: Gather feedback, fix issues
3. **Default Switch**: Make Textual the default (keep Questionary via `--questionary` flag)
4. **Deprecation**: Announce Questionary deprecation
5. **Removal**: Remove Questionary code

---

## 10. Success Criteria

The migration will be considered successful when:

1. **Functional Completeness**:
   - All existing features work in Textual mode
   - No regressions in Questionary mode
   - All tests pass

2. **User Experience**:
   - Textual UI is intuitive and responsive
   - Progress feedback is clear during operations
   - Error messages are helpful

3. **Code Quality**:
   - Linting passes (Ruff)
   - Type checking passes (Pyright)
   - Code follows project conventions

4. **Documentation**:
   - README updated with Textual usage
   - AGENTS.md updated with Textual patterns
   - Code is well-commented

5. **Performance**:
   - App launches quickly
   - Discovery operations don't block UI
   - Large guest lists render smoothly

---

## 11. Appendix

### 11.1 Textual Resources

- [Textual Documentation](https://textual.textual.io/)
- [Textual Widget Gallery](https://textual.textual.io/gallery/)
- [Textual Examples](https://github.com/Textualize/textual/tree/main/examples)

### 11.2 Questionary to Textual Quick Reference

| Questionary | Textual | Notes |
|-------------|---------|-------|
| `questionary.text()` | `Input` widget | Add validator for required |
| `questionary.select()` | `Select` widget | Map choices to options |
| `questionary.confirm()` | `Switch` widget | More intuitive for yes/no |
| `questionary.print()` | `Rich` widget or `Static` | Use Rich for styling |
| `questionary.path()` | `Input` with path validator | Custom validator needed |
| `questionary.checkbox()` | `Checkbox` widget | Similar behavior |

### 11.3 Glossary

- **TUI**: Terminal User Interface
- **Screen**: A full-screen view in Textual
- **Widget**: A reusable UI component in Textual
- **Worker**: A background thread for blocking operations
- **Message**: Textual's event system for communication
- **Binding**: Keyboard shortcut mapping

---

## Conclusion

This migration plan provides a comprehensive roadmap for replacing Questionary with Textual in [`proxmox_inventory_builder.py`](../proxmox_inventory_builder.py). The phased approach ensures a smooth transition with minimal risk, while the detailed technical guidance provides everything needed for implementation.

The key benefits of this migration include:

1. **Modern TUI**: Rich, responsive terminal interface
2. **Better UX**: Improved navigation and feedback
3. **Async Support**: Native async/await integration
4. **Extensibility**: Easy to add new features
5. **Maintainability**: Cleaner code structure

Following this plan will result in a modern, user-friendly inventory builder that maintains all existing functionality while providing a superior user experience.
