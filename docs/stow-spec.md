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

### `stow restore`

Restore the symlinks for a package from the most recent backup.

**Parameters:**
- `package` (required): Package name

**Options:**
- `--target`: Target directory (default: `~`)
- `--source-dir`: Source directory (default: `~/.local/share/linux-config`)
- `--backup-dir`: Backup directory (default: `~/.local/share/stow-backups`)

**Behavior:**
1. Collects all files mapped to the package.
2. Searches the backup directory for the newest timestamped backup matching each file.
3. Fails loudly with an explicit error if any mapped file lacks a valid backup.
4. Safely destroys the current target symlink/file and restores the backup.

## Examples

```nu
stow add vim ~/.vimrc
stow add nvim ~/.config/nvim/init.vim
stow apply vim
stow apply nvim --backup-dir ~/.backups
stow apply nvim --backup-dir ~/.backups --target ~/foo-bar

# Restoring
stow restore vim
stow restore nvim --backup-dir ~/.backups --target ~/foo-bar
```

## Core Philosophy (stow.nu vs chezmoi)

`stow.nu` is designed as a modernized, stateless, Nushell-native implementation of GNU Stow principles. It is specifically built for transparent "live-editing" using raw symlinks, contrasting with state-driven tools like `chezmoi`.

Key differentiators:
1. **Stateless Symlinking:** Applying a package maps symlinks into the target directory safely. Editing a config locally means explicitly editing the central repository copy, avoiding out-of-sync drifts. Tools like `chezmoi` use state databases and standalone copies tracking hashes and permissions.
2. **Raw Configurations:** `stow.nu` treats managed dotfiles as 1:1 identical strings. It does not employ Go templating or secret-injection logic during deploy.
3. **`dot-` Expansion:** `stow.nu` forces visibility on staged dotfiles via the `dot-` prefix pattern (i.e. `dot-bashrc`), similar to the `dot_` mechanism seen in other toolchains, making globbing safer and preventing hidden dotfile clusters in repository root paths.

## Notes

- Only files are allowed (directories not supported)
- Files in target matching stow files are backed up before linking
- Backup format: `<relative-path>-YYYYMMDD_HHMMSS`

## Inner Workings (Developer)

The logic governing `stow.nu` revolves around strict relative destination linking, safe path manipulation, and aggressive collision backups.

To aid maintainability, below is an exhaustive breakdown of how the most complex internal functions operate to achieve this:

### 1. `compute-stow-path` (Adding to the staging area)
This function determines where a file should live inside the tracked package repository when a user calls `stow add`.

It strictly enforces `path relative-to` boundaries. If a user tries to bundle a file that cannot be mathematically resolved against the target root (e.g., trying to execute `stow add nvim /etc/fstab` while `--target` is `~`), `compute-stow-path` traps the cross-bound attempt and throws an explicit terminating error.

Assuming the path is safely within the target boundary, the function explodes the valid relative path into segments and applies `to-stow-name` on every segment. This converts any folder or file that natively starts with a `.` into a `dot-` equivalent.
* **Example:** `~/.config/nvim/init.vim` mathematically reduces to `.config/nvim/init.vim`, and is successfully transformed into `dot-config/nvim/init.vim` inside the internal repository. This ensures visibility in graphical file managers and prevents native command-line recursive globs from skipping dotfiles.

### 2. `collect-stow-files` (Crawling the staging area)
This is the workhorse behind `stow apply` and `stow restore`. It takes an absolute package directory (e.g., `~/.local/share/linux-config/nvim`) and recursively finds all files inside it using Nushell's native `**/*` glob string.

Because `compute-stow-path` replaced all starting dots with `dot-` prefixes, `**/*` captures everything reliably without needing special hidden file flags.

Once the files are listed, `collect-stow-files` applies the inverse macro: `from-stow-name`. It maps the internal repository location back to what its true deployed target path should look like on the system (`dot-config` becomes `.config`). Critically, this function drops all generic directory objects from the output stream. It *only* streams file objects, effectively preventing symlinks from hijacking entire folders like `~/.config`.

### 3. `backup-file` (Collision management during apply)
Before `stow apply` generates a new symlink to a deployed path, it calls `backup-file` on the target location.
* If a symlink already exists there, it is silently deleted (assumed to be a stale stow or safe overwrite).
* If a genuine file exists there, its relative deployment path is calculated, and a formatted timestamp (`-YYYYMMDD_HHMMSS`) is appended to it. It is copied deep into the `$backup_dir` folder tree (e.g. `~/.local/share/stow-backups/.config/nvim/init.vim-2026...`), preventing data loss. Only after that copy perfectly succeeds is the target file forcefully deleted.

### 4. `main restore` (Rollback mechanism)
The restore command exists as an "undo" lever. Because `stow apply` inherently leaves old, timestamped copies of overwritten files inside the backup directory, `main restore` traces them down.

For a requested package, it passes the package name into `collect-stow-files` to determine exactly which files the package owns. For each file mapping, it dives into the backup directory and does a timestamp-glob search (e.g., `glob ~/.local/share/stow-backups/.config/nvim/init.vim-*`).

It then chronologically sorts these matches and picks the newest one. If it cannot find a valid timestamped backup file for *any* required component in the package, the script fails loudly with an explicit `Cannot restore package` exception to prevent partial/corrupted un-stow operations. If all backups are located safely, it deletes the current active symlinks and copies the backup files back into their original locations.
