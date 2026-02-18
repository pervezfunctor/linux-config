# AGENTS.md

This document provides guidelines for AI agents working on this dotfiles repository. It outlines the repository structure, coding conventions, and patterns to follow when making changes.

## Repository Overview

This is a GNU Stow-managed dotfiles repository (`linux-config`) containing configuration files for various applications and tools. The repository is organized by application/tool, with each directory following a consistent structure for easy stowing to `$HOME`.

## Repository Structure

```
linux-config/
├── bin/                    # Bootstrap and setup scripts
├── home-manager/           # Nix Home Manager configuration
├── hypr/                   # Hyprland window manager config
├── kitty/                  # Kitty terminal emulator config
├── mango/                  # Mango window manager config
├── niri/                   # Niri window manager config
├── nushell/                # Nushell shell config
├── systemd/                # Systemd user units
├── vscode/                 # VSCode settings
├── xdg/                    # XDG desktop portal config
├── zed/                    # Zed editor settings
├── zsh/                    # Zsh config
├── .stowrc                  # Stow configuration
├── .stow-local-ignore       # Stow ignore patterns
└── README.md                # Repository documentation
```

### Directory Naming Convention

Each application/tool directory follows this pattern:

```
<appname>/
└── dot-config/
    └── <appname>/
        ├── config.<ext>              # Main config file
        └── config/                   # Modular config subdirectory
            ├── binds.<ext>           # Keybindings
            ├── env.<ext>             # Environment variables
            ├── exec.<ext>            # Autostart commands
            ├── io.<ext>              # Input/output settings
            ├── rules.<ext>           # Window/app rules
            └── ui.<ext>              # UI/theme settings
```

For non-config files (e.g., zsh):
```
<appname>/
└── dot-<filename>                    # Direct file placement
```

## Coding Styles

### Nushell (`.nu` files)

**Indentation**: 2 spaces

**Function Definition**:
```nu
def function-name [param: type] {
    let variable = value
    # function body
}
```

**Variables**: Use `let` for declarations
```nu
let jupyter_dir = ($nu.home-dir | path join jupyter-lab)
```

**External Commands**: Prefix with `^`
```nu
^$jupyter lab
```

**Path Operations**: Use `| path join`
```nu
let config_path = ($nu.default-config-dir | path join aliases.nu)
```

**Error Handling**:
```nu
if not ($path | path exists) {
    error make {
        msg: "Directory does not exist"
        label: {
            text: $path
            span: (metadata $path).span
        }
    }
}
```

**Aliases**:
```nu
alias c = code
alias g = git
```

**Sourcing Files**: Place at the bottom of main config
```nu
source ($nu.default-config-dir | path join auto-includes.nu)
source ($nu.default-config-dir | path join aliases.nu)
```

**Comments**: Use `#` for single-line comments
```nu
# This is a comment
```

#### Functional Programming Techniques

**Library Files**:
- Use `bin/lib.nu` for general reusable functions
- Use `bin/logs.nu` for logging functions

**Imports**:
```nu
use ./lib.nu [
    default-if-empty
    try-relative
    validate-path
]
use ./logs.nu
```

**Avoid Mutation**: Use pipelines instead of `mut` + `for` + `append`
```nu
# Bad
mut items = []
for item in $collection {
    $items = ($items | append (transform $item))
}

# Good - use pipeline with | each
let items = ($collection | each { |item| transform $item })
```

**Pure Functions**: Separate pure logic from side effects
```nu
# Pure - no side effects, returns value
def compute-path [base: string, name: string] {
    $base | path join $name
}

# Impure - I/O side effects
def link-files [items: list<record>] {
    for item in $items {
        ^ln -sf $item.src $item.dest
    }
}
```

**Safe Command Wrappers**: Wrap external commands for consistent error handling
```nu
def safe-ln [src: string, dest: string] {
    try {
        ^ln -sf $src $dest
        true
    } catch {
        false
    }
}
```

**Default Values**: Use `default-if-empty` for pipe-friendly defaults
```nu
let dir = ($input | default-if-empty $env.HOME)
```

**Validation Functions**: Centralize validation logic
```nu
def validate-path [path: string, --required] {
    if $required and not ($path | path exists) {
        error make {
            msg: $"Path does not exist: ($path)"
            label: { text: $path, span: (metadata $path).span }
        }
    }
    $path
}
```

**Avoid `reduce`**: Use `| each`, `| where`, `| get`, or `| reduce` alternatives instead
```nu
# Bad - avoid reduce for simple transformations
let result = ($items | reduce -f [] { |item, acc| $acc | append $item })

# Good - use | each
let result = ($items | each { |item| transform $item })

# Good - use | where for filtering
let filtered = ($items | where { |item| $item.active })

# Good - use | get for indexing
let value = ($record | get $key | default "fallback")
```

**Pipeline-First**: Prefer passing data through pipes rather than nested function calls
```nu
# Good
let result = ($input | step-one | step-two | step-three)

# Avoid
let result = (step-three (step-two (step-one $input)))
```

**Testing**: Write tests for functions in `<script>-test.nu`
```nu
# bin/stow-test.nu
use ./stow-lib.nu

def "test to-stow-name" [] {
    let result = (to-stow-name ".bashrc")
    assert equal $result "dot-bashrc"
}
```

### KDL (`.kdl` files)

**Indentation**: 4 spaces

**Include Directive**: Use for modular configs
```kdl
include "config/env.kdl"
include "config/io.kdl"
include "config/ui.kdl"
```

**Node Structure**:
```kdl
binds {
    Mod+Return { spawn "kitty"; }
    Mod+Q { close-window; }
}
```

**Comments**: Use `//` for single-line comments
```kdl
// This is a comment
```

**Keybinding Format**:
```kdl
Mod+Key { action; }
Mod+Shift+Key { action; }
```

**Parameters**:
```kdl
Mod+WheelScrollDown cooldown-ms=150 { focus-workspace-down; }
```

### Bash (`.sh` files)

**Indentation**: 2 spaces

**Shebang**:
```bash
#!/usr/bin/env bash
```

**Function Definition**:
```bash
function_name() {
  local variable
  variable=$(command)
  # function body
}
```

**Command Substitution**:
```bash
pkgmgr=$(detect_pkgmgr)
```

**Conditional Statements**:
```bash
if [ -z "$pkgmgr" ]; then
  echo "Error: No supported package manager found"
  exit 1
fi
```

**Case Statements**:
```bash
case "$pkgmgr" in
apt-get)
  sudo apt-get update && sudo apt-get install -y git bash
  ;;
dnf)
  sudo dnf install -y git bash
  ;;
esac
```

**Comments**: Use `#` for single-line comments
```bash
# Check and install git and bash
```

### Nix (`.nix` files)

**Indentation**: 2 spaces

**Attribute Set**:
```nix
{
  description = "Home Manager flake configuration";
  inputs = { ... };
  outputs = { ... };
}
```

**Let Expressions**:
```nix
let
  system = "x86_64-linux";
  pkgs = import nixpkgs { inherit system; };
in
{
  # body
}
```

**Function Arguments**:
```nix
outputs = { nixpkgs, home-manager, ... }@inputs: { ... }
```

**Inherit Keyword**:
```nix
inherit pkgs;
inherit system;
```

**Lists**:
```nix
modules = [
  ./dev.nix
  ./packages.nix
]
```

**Comments**: Use `#` for single-line comments
```nix
# This is a comment
```

## Common Patterns

### Modular Configuration

Split large configuration files into logical modules:

1. **Main config file** (`config.kdl`, `config.nu`, etc.) - includes all modules
2. **binds** - Keybindings and shortcuts
3. **env** - Environment variables
4. **exec** - Autostart commands
5. **io** - Input/output settings
6. **rules** - Window/application rules
7. **ui** - UI and theme settings

### Cross-Platform Support

When writing scripts that need to work across different distributions:

```bash
detect_pkgmgr() {
  if command -v apt-get >/dev/null 2>&1; then
    echo "apt-get"
  elif command -v dnf >/dev/null 2>&1; then
    echo "dnf"
  elif command -v pacman >/dev/null 2>&1; then
    echo "pacman"
  elif command -v zypper >/dev/null 2>&1; then
    echo "zypper"
  else
    echo ""
  fi
}
```

### Command Existence Check

**Bash**:
```bash
if ! command -v git >/dev/null 2>&1; then
  echo "git not found"
fi
```

**Nushell**:
```nu
def has_cmd [app: string] {
    (which $app | is-not-empty)
}
```

## File Naming Conventions

- **Config files**: `config.<ext>` (e.g., `config.kdl`, `config.nu`)
- **Modular configs**: `config/<category>.<ext>` (e.g., `config/binds.kdl`)
- **Scripts**: Use lowercase with hyphens (e.g., `bootstrap`, `ct-setup`)
- **Aliases**: `aliases.nu`
- **Environment**: `env.nu`

## Stow Integration

When adding new configurations:

1. Create directory: `<appname>/dot-config/<appname>/`
2. Place config files inside
3. Run `stow <appname>` from repository root to symlink
4. Test configuration before committing

### stow.nu Tool

This repository includes a custom Nushell-based stow implementation (`bin/stow.nu`) for managing dotfiles with symlinks.

**Syntax:**
```
stow add <package> <path>
stow apply <package> [--target <dir>] [--source-dir <dir>] [--backup-dir <dir>]
```

**Commands:**
- `stow add <package> <path>` - Add a file to a stow package
- `stow apply <package>` - Apply stow package with automatic backup

**Options:**
- `--target`: Target directory (default: `~`)
- `--source-dir`: Source directory (default: `~/.local/share/linux-config`)
- `--backup-dir`: Backup directory for apply (default: `~/.local/share/stow-backups`)

**Examples:**
```nu
stow add vim ~/.vimrc
stow add nvim ~/.config/nvim/init.vim
stow apply vim
stow apply nvim --backup-dir ~/.backups
```

**Notes:**
- Only files are allowed (directories not supported)
- Files in target matching stow files are backed up before linking
- Backup format: `<relative-path>-YYYYMMDD_HHMMSS`

## DMS Integration

This repository uses the DMS (Desktop Management System) for various desktop functions:

- **Spotlight**: Application launcher (`dms ipc call spotlight toggle`)
- **Lock**: Screen locking (`dms ipc call lock lock`)
- **Clipboard**: Clipboard manager (`dms ipc call clipboard toggle`)
- **Audio**: Volume control (`dms ipc call audio increment/decrement/mute`)
- **Brightness**: Brightness control (`dms ipc call brightness increment/decrement`)
- **Notifications**: Notification center (`dms ipc call notifications toggle`)

## Package Management

The repository uses:
- **pikman**: Custom package manager wrapper
- **pixi**: Global package installation (`pixi global install`) and project-local Conda/PyPI envs (e.g. `py/pixi.lock`)
- **uv**: Python package management (`uv tool run`, `uvx`); uv drives PyPI deps while pixi layers Conda packages + uv integration.

## Keybinding Conventions

- **Mod**: Super/Windows key
- **Alt**: Alt key
- **Ctrl**: Control key
- **Shift**: Shift key
- **Directional**: Arrow keys, H/J/K/L (vim-style)

Common patterns:
- `Mod+Key`: Primary action
- `Mod+Shift+Key`: Secondary/alternative action
- `Mod+Ctrl+Key`: Tertiary action
- `Mod+Alt+Key`: Monitor/workspace actions

## Testing Guidelines

Before committing changes:

1. **Syntax check**: Ensure config files are syntactically valid
2. **Stow test**: Run `stow -n <appname>` to test without applying
3. **Reload**: Reload affected applications (e.g., `niri msg reload-config`)
4. **Functionality**: Test all modified features
5. **pixi check**: From `py/`, run `pixi run check` after every change to execute the consolidated lint/type/test suite

## Proxmox Automation CLI

The Python helpers under `py/` are now exposed via a unified Typer CLI named `proxmoxctl`. Run it with `uv run proxmoxctl -- --help` to view available commands. Key subcommands:

- `proxmoxctl maintenance run`: single-host lifecycle orchestration (wraps `proxmox_maintenance.py`).
- `proxmoxctl batch run`: fan-out executor for every host defined in `proxmox-hosts.toml`.
- `proxmoxctl wizard run`: launches the interactive manifest editor.
- `proxmoxctl inventory configure`: guided guest discovery/credential capture.

Legacy scripts (`proxmox_maintenance.py`, `proxmox_batch.py`, etc.) remain runnable for backwards compatibility, but new work should target `proxmoxctl` so we keep the UX consistent and typed via Pydantic.

## Git Workflow

- Branch naming: `feature/<description>` or `fix/<description>`
- Commit messages: Use present tense, imperative mood
  - "Add keybinding for application launcher"
  - "Fix path resolution in bootstrap script"
- Pull requests: Describe changes clearly

## Common Tools Referenced

- **btm**: Bottom system monitor (alias: `h`)
- **fd-find**: File finder (alias: `f`)
- **rg**: Ripgrep (alias: `s`)
- **nvim**: Neovim (alias: `v`)
- **tmux**: Terminal multiplexer (alias: `t`)
- **jupyter**: Jupyter Lab
- **marimo**: Python notebook tool

## Additional Resources

- [GNU Stow Documentation](https://www.gnu.org/software/stow/manual/)
- [Nushell Documentation](https://www.nushell.sh/book/)
- [Niri Documentation](https://niri.friedl.at/)
- [Home Manager Manual](https://nix-community.github.io/home-manager/)
