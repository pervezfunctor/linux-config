# stow Specification

GNU Stow wrapper functions for managing dotfiles in nushell.

## Overview

These functions simplify the workflow of converting existing dotfiles to GNU Stow packages and applying them safely with automatic backups.

## Functions

### `stow`

Convert existing files/directories to a stow-compatible package structure.

**Signature:**
```nu
stow <path> [--target-dir <dir>] [--package <name>] [--stow-dir <dir>]
```

**Parameters:**
- `path` (required): Source path to convert (e.g., `~/.config/nvim`)
- `--target-dir` (optional): Target directory where files will be stowed (default: `~`)
- `--package` (optional): Stow package name. Defaults to basename of `path`
- `--stow-dir` (optional): Stow directory. Defaults to `~/.local/share/linux-config`

**Behavior:**
1. Validates that source path exists
2. Creates stow package directory structure
3. Converts dotfile names to stow-compatible format (leading `.` → `dot-`)
4. Copies file contents (not just creates empty files)
5. Runs `stow --adopt` to integrate existing files into the package

**Naming Convention:**
- `.vimrc` → `dot-vimrc`
- `.config/nvim` → `dot-config/nvim`
- `normal-file` → `normal-file` (unchanged)

**Usage:**
```nu
# Basic usage (defaults to ~ as target)
stow ~/.vimrc --package vim

# With nested structure
stow ~/.config/nvim --target-dir ~ --package nvim

# Custom stow directory
stow ~/.config/fish --target-dir ~ --package fish --stow-dir ~/dotfiles
```

### `stow apply`

Apply a stow package with automatic backup of conflicting files.

**Signature:**
```nu
stow apply <package> [--target-dir <dir>] [--stow-dir <dir>] [--backup-dir <dir>]
```

**Parameters:**
- `package` (required): Stow package name to apply
- `--target-dir` (optional): Target directory. Defaults to `~`
- `--stow-dir` (optional): Stow directory. Defaults to `~/.local/share/linux-config`
- `--backup-dir` (optional): Backup location. Defaults to `~/.local/share/stow-backups`

**Behavior:**
1. Discovers all files in the stow package
2. For each file that conflicts in the target:
   - Backs up only files (not directories)
   - Backup path preserves directory structure relative to target
   - Backup format: `<relative-path>-YYYYMMDD_HHMMSS`
   - Removes the original file
3. Runs `stow` to create symlinks
4. Reports number of files backed up and location

**Important:** Only backs up files, not directories. This prevents accidentally moving entire directory trees.

**Usage:**
```nu
# Basic usage (defaults to ~ as target)
stow apply vim

# With custom backup location
stow apply nvim --target-dir ~ --stow-dir ~/dotfiles --backup-dir ~/.backups

# Apply to specific target directory
stow apply fish --target-dir ~
```

### `stow help`

Show help message with usage information.

**Signature:**
```nu
stow help
```

## Implementation Details

### Helper Functions

#### `to-stow-name`
Converts a filename to stow-compatible format.
- Input: `.vimrc` → Output: `dot-vimrc`
- Input: `normal-file` → Output: `normal-file`

#### `from-stow-name`
Converts from stow naming back to original.
- Input: `dot-vimrc` → Output: `.vimrc`
- Input: `normal-file` → Output: `normal-file`

#### `create-stow-structure`
Recursively creates stow-compatible directory structure.
- Handles arbitrarily deep nesting
- Converts each path component using `to-stow-name`
- Copies file contents using `open --raw` and `save`

#### `get-stow-files`
Returns all files from a stow package (excludes directories).
- Skips the package root directory itself
- Returns original target paths for each file

#### `backup-path`
Backs up a single file with timestamp.
- Only processes files (skips directories)
- Creates backup directory structure if needed
- Preserves directory structure relative to target_dir
- Uses format: `<relative-path>-YYYYMMDD_HHMMSS`

## Technical Notes

**Nushell Version:** 0.110.0

**Key Syntax:**
- External commands: `^stow`, `^cp`, `^rm -f`
- Path joining with spread: `path join ...$parts`
- Pipeline input: Functions use `$in` for piped data

**Stow Flags Used:**
- `--adopt`: Import existing files into stow package
- `--no-folding`: Prevent directory folding
- `-d <dir>`: Specify stow directory
- `-t <dir>`: Specify target directory

## Test Coverage

Implementation tested with 12 tests covering:

- Name conversions (dotfiles ↔ stow names)
- Round-trip conversions
- Stow package creation
- Content preservation
- Backup functionality with path preservation
- Stow-apply with conflicts
- File discovery from packages
- Boundary conditions (empty packages, non-existent paths)

**Results:** 12 tests defined, all passing

## Examples

### Converting vim configuration to stow
```nu
stow ~/.vimrc --package vim
```
Creates:
```
vim/
└── dot-vimrc    # Contains content from ~/.vimrc
```

### Converting nested config directory
```nu
stow ~/.config/nvim --target-dir ~ --package nvim
```
Creates:
```
nvim/
└── dot-config/
    └── nvim/
        └── init.lua
```

### Applying with backup
```nu
stow apply fish --target-dir ~
```
If `~/.config/fish/config.fish` exists:
1. Backs up to `~/.local/share/stow-backups/.config/fish/config.fish-20260217_123456`
2. Removes original file
3. Creates symlink: `~/.config/fish/config.fish → ~/.local/share/linux-config/fish/dot-config/fish/config.fish`
