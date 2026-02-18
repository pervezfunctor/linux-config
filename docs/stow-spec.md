# stow Specification

Dotfiles manager with symlink creation (pure Nushell implementation).

## Overview

Manages dotfiles by creating symlinks from a source directory to target locations, with automatic dot-prefix conversion.

## Syntax

```
stow add <package> <path>
stow apply <package> [--target <dir>] [--source-dir <dir>] [--backup-dir <dir>]
```

## Commands

### `stow add`

Add a file to a stow package.

**Parameters:**
- `package` (required): Package name
- `path` (required): File path to add

**Options:**
- `--target`: Target directory (default: `~`)
- `--source-dir`: Source directory (default: `~/.local/share/linux-config`)

**Behavior:**
1. Validates path exists and is a file
2. Copies file to source package directory with dot-prefix conversion
3. Creates symlink in target directory

### `stow apply`

Apply a stow package with automatic backup.

**Parameters:**
- `package` (required): Package name

**Options:**
- `--target`: Target directory (default: `~`)
- `--source-dir`: Source directory (default: `~/.local/share/linux-config`)
- `--backup-dir`: Backup directory (default: `~/.local/share/stow-backups`)

## Examples

```nu
stow add vim ~/.vimrc
stow add nvim ~/.config/nvim/init.vim
stow apply vim
stow apply nvim --backup-dir ~/.backups
stow apply nvim --backup-dir ~/.backups --target ~/foo-bar
```

## Notes

- Only files are allowed (directories not supported)
- Files in target matching stow files are backed up before linking
- Backup format: `<relative-path>-YYYYMMDD_HHMMSS`
