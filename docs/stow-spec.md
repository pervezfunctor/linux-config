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
5. Preserves symlinks as symlinks (does not convert to regular files)
6. Runs `stow --adopt` to integrate existing files into the package

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
   - Backs up only regular files (not directories or symlinks)
   - Removes unmanaged symlinks (stow will create its own)
   - Backup path preserves directory structure relative to target
   - Backup format: `<relative-path>-YYYYMMDD_HHMMSS`
   - Removes the original file
3. Runs `stow` to create symlinks
4. Reports number of files backed up and location

**Important:** Only backs up regular files. Symlinks are removed since stow will create its own.

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
