# stow Specification

Dotfiles manager that stages files into package directories and deploys them with symlinks.

## Overview

`stow.nu` manages dotfiles by:

1. storing package contents under a source directory,
2. translating leading `.` path segments to `dot-` inside the repository,
3. applying packages by creating symlinks into a target directory,
4. backing up replaced real files before linking.

## Syntax

```nu
stow add <package> <path> [--target <dir>] [--source-dir <dir>]
stow apply <package> [--target <dir>] [--source-dir <dir>] [--backup-dir <dir>]
stow remove <package> [--target <dir>] [--source-dir <dir>] [--backup-dir <dir>]
stow status <package> [--target <dir>] [--source-dir <dir>] [--backup-dir <dir>]
stow doctor <package> [--target <dir>] [--source-dir <dir>] [--backup-dir <dir>]
stow restore <package> [--target <dir>] [--source-dir <dir>] [--backup-dir <dir>]
```

## Commands

### `stow add`

Adds a target-path file into a package and replaces the original path with a symlink to the staged copy.

**Parameters**
- `package`: package name; required and must be non-empty
- `path`: path to add; must resolve under `--target`

**Accepted inputs**
- regular files

**Rejected inputs**
- directories
- symlinks to files
- symlinks to directories
- broken symlinks

**Behavior**
1. Validates the requested path.
2. Computes the staged path under `<source-dir>/<package>/...` using `dot-` conversion.
3. Copies regular-file inputs into the staging area using metadata-preserving filesystem copy semantics (`cp -p`), preserving mode bits such as executability.
4. Replaces the target path with a symlink to the staged item.
5. Fails if `path` is not a regular file, including when it is already a symlink.

### `stow apply`

Applies every staged item from a package into the target directory.

**Behavior**
1. Fails if the package does not exist.
2. Enumerates staged package items recursively.
3. Removes pre-existing symlinks at destination paths.
4. Backs up pre-existing regular files before linking.
5. Fails on directory collisions.
6. Creates symlinks from each target path to the staged item.

### `stow remove`

Removes deployed symlinks for a package from the target directory and restores backups when available.

**Behavior**
1. Fails if the package does not exist.
2. Enumerates the package's staged paths and corresponding target paths.
3. Refuses to delete a target unless it is the exact symlink currently managed by that package.
4. Removes managed symlinks.
5. Restores the newest valid timestamped backup for each path when one exists.
6. If no backup exists, leaves the target path absent after removing the managed symlink.
7. Fails if backup data for a path exists but has no valid timestamp.
8. Fails on directory collisions or other unmanaged target drift.

### `stow status`

Reports the current per-target state for every staged path in a package.

**Behavior**
1. Fails if the package does not exist.
2. Enumerates the package's staged paths and corresponding target paths.
3. Returns one record per path with:
   - `target`: target path
   - `stow`: staged source path
   - `state`: one of `managed`, `missing`, `file`, `directory`, `foreign-symlink`
   - `link_target`: the current symlink target when the target is a symlink, otherwise empty
   - `backup_status`: one of `found`, `missing`, `invalid`
   - `backup_path`: newest valid backup path when found, otherwise empty

### `stow doctor`

Checks whether a package is deployed cleanly to the target directory.

**Behavior**
1. Uses the same per-target inspection data as `stow status`.
2. Succeeds when every target is in `managed` state and no path has `backup_status = invalid`.
3. Prints the unhealthy path records before failing.
4. Exits non-zero when any target is missing, replaced by a regular file, replaced by a foreign symlink, blocked by a directory, or has invalid backup data.

### `stow restore`

Restores the newest available backups for paths owned by a package.

**Behavior**
1. Fails if the package does not exist.
2. Enumerates the package's staged paths and corresponding target paths.
3. Searches for backups only within that package's backup namespace.
4. Restores the newest valid timestamped backup for each path, preferring the highest collision suffix when multiple backups share the same timestamp.
5. If no backup exists and the current target is a regular file, fails with a non-zero error.
6. If no backup exists and the current target is a symlink or missing, warns and skips that path.
7. Fails on directory collisions during restore.

## Options

- `--target`: target directory, default `~`
- `--source-dir`: source directory, default `~/.local/share/linux-config`
- `--backup-dir`: backup directory for `apply`, `remove`, `status`, `doctor`, and `restore`, default `~/.stow-backups`

## Backup layout

Regular files replaced by `stow apply` are backed up under:

```text
<backup-dir>/<package>/<target-scope>/<relative-target-path>-YYYYMMDD_HHMMSS[-N]
```

Examples:
- `~/.stow-backups/vim/_root_/home/alice/.vimrc-20260308_120000`
- `~/.stow-backups/vim/_root_/home/alice/.vimrc-20260308_120000-1`
- `~/.stow-backups/nvim/_root_/home/alice/.config/nvim/init.lua-20260308_120000`

Existing destination symlinks are removed and replaced directly; they are not copied into the backup directory.
The `target-scope` segment is derived from the absolute `--target` path so the same package can be applied to multiple target roots without sharing backups.
If a backup path for the current second already exists, `stow` appends `-1`, `-2`, and so on to preserve every backup instead of overwriting an older one.

## Notes

- Repository paths use `dot-` prefixes instead of leading dots.
- Deployed links are symlinks to staged items in the source directory.
- Major validation failures terminate the command with a non-zero exit.

## Examples

```nu
stow add vim ~/.vimrc
stow add nvim ~/.config/nvim/init.lua
stow add shell ~/.aliases

stow apply vim
stow apply nvim --target ~/tmp-home --backup-dir ~/.backups

stow remove vim
stow remove nvim --target ~/tmp-home --backup-dir ~/.backups

stow status vim
stow doctor nvim --target ~/tmp-home --backup-dir ~/.backups

stow restore vim
stow restore nvim --target ~/tmp-home --backup-dir ~/.backups
```
