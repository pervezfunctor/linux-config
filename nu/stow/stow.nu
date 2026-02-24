#!/usr/bin/env nu
# stow.nu requires running from bin/ directory or use: nu -I ./bin stow.nu

use ../lib/lib.nu [
    ensure-parent-dir
    validate-path
    validate-file
    default-if-empty
]
use ../lib/logs.nu [log+ error+]

# Resolves target, source, and backup directories to their final absolute
# or default paths. If no custom paths are provided, defaults to $env.HOME
# and its .local/share subdirectories.
#
# Example:
#   resolve-dirs --target "/opt"
#   # => {
#   #   target: "/opt",
#   #   source: "/home/user/.local/share/linux-config",
#   #   backup: "/home/user/.stow-backups"
#   # }
def resolve-dirs [
    target: string = "",
    source_dir: string = "",
    --backup-dir: string = ""
] {
    {
        target: ($target | default-if-empty $env.HOME)
        source: (
            $source_dir
            | default-if-empty (
                $env.HOME
                | path join '.local' 'share' 'linux-config'
            )
        )
        backup: (
            $backup_dir
            | default-if-empty ($env.HOME | path join '.stow-backups')
        )
    }
}

def to-stow-name [name: string] {
    if ($name | str starts-with '.') {
        $"dot-($name | str substring 1..)"
    } else {
        $name
    }
}

def from-stow-name [name: string] {
    if ($name | str starts-with 'dot-') {
        $".($name | str substring 4..)"
    } else {
        $name
    }
}

# Computes the destination path inside the stow staging package for a given
# file. Validates that the file being added is safely inside the target
# boundary. Replaces hidden dot-directories with 'dot-' prefixed folders to
# allow safe globbing.
#
# Example:
#   compute-stow-path {
#       path: "/home/user/.config/nvim/init.lua",
#       target: "/home/user",
#       source_dir: "/home/user/stiffs",
#       package: "nvim"
#   }
#   # => "/home/user/stiffs/nvim/dot-config/nvim/init.lua"
def compute-stow-path [
    ctx: record<
        path: string,
        target: string,
        source_dir: string,
        package: string
    >
] {
    $ctx.source_dir | path join $ctx.package | path join ...(try {
        $ctx.path | path relative-to $ctx.target
    } catch {
        error make {
            msg: (
                $"Path ($ctx.path) is outside the target "
                + $"directory ($ctx.target)"
            )
            label: {
                text: ($ctx.path)
                span: (metadata $ctx.path).span
            }
        }
    } | path split | each { |p| to-stow-name $p })
}

# Calculates the final symlink exact destination inside the target
# deployment boundary.
#
# Example:
#   compute-target-link "/home/user" "/home/user/.config/nvim/init.lua"
#   # => "/home/user/.config/nvim/init.lua"
def compute-target-link [expanded_target: string, expanded_path: string] {
    $expanded_target | path join (try {
        $expanded_path | path relative-to $expanded_target
    } catch {
        error make {
            msg: (
                $"Path ($expanded_path) is outside the target "
                + $"directory ($expanded_target)"
            )
            label: {
                text: $expanded_path
                span: (metadata $expanded_path).span
            }
        }
    })
}

# Crawls a staged stow package directory and computes the source and
# intended target mapping for every file. Automatically transforms 'dot-'
# archive names back to '.' hidden paths for the final deployment target.
#
# Example:
#   collect-stow-files "/home/user/stow/nvim" "/home/user"
#   # => [
#   #   {
#   #     stow: "/home/user/stow/nvim/dot-config/init.lua",
#   #     target: "/home/user/.config/init.lua"
#   #   }
#   # ]
def collect-stow-files [abs_stow_pkg: string, abs_target: string] {
    glob $"($abs_stow_pkg)/**/*"
    | where { |item|
        ($item | path type) != 'dir' and $item != $abs_stow_pkg
    }
    | each { |item|
        {
            stow: $item,
            target: ($abs_target | path join ...(
                $item
                | path relative-to $abs_stow_pkg
                | path split
                | each { |p| from-stow-name $p }
            ))
        }
    }
}

# Safely handles file collisions before a stow symlink is injected.
# If a pre-existing target file is a symlink, it is silently destroyed.
# If a pre-existing target file is a real file, it is timestamped, copied to
# `backup_dir`, and then destroyed.
#
# Example:
#   backup-file "/home/user/.bashrc" "/home/user" "/home/user/backups"
#   # Backs up the real file to
#   # "/home/user/backups/.bashrc-20230501_120000" and deletes original file.
def backup-file [file: string, abs_target: string, backup_dir: string] {
    let file_type = do -i { $file | path type } | default "none"
    if $file_type == 'symlink' {
        ^rm -f $file
        true
    } else if $file_type == 'file' {
        if not ($backup_dir | path exists) {
            mkdir $backup_dir
        }
        let timestamp = (date now | format date '%Y%m%d_%H%M%S')
        let rel_path = (($file | path expand) | path relative-to $abs_target)
        let backup_path = $backup_dir | path join $"($rel_path)-($timestamp)"
        ensure-parent-dir $backup_path
        ^cp $file $backup_path
        ^rm -f $file
        true
    } else if $file_type == 'dir' {
        error make {
            msg: (
                $"Destination is a directory, cannot "
                + $"replace with symlink: ($file)"
            )
            label: { text: $file, span: (metadata $file).span }
        }
    } else {
        true
    }
}

def link-files [items: list<record<stow: string, target: string>>] {
    for item in $items {
        ensure-parent-dir $item.target
        ^ln -sf $item.stow $item.target
    }
}

export def "main add" [
    package: string,
    path: string,
    --target: string,
    --source-dir: string
] {
    let dirs = (resolve-dirs $target $source_dir)

    try {
        validate-path $path
        validate-file $path
    } catch { |e|
        error+ $e.msg
        return
    }

    let expanded_path = ($path | path expand)
    let expanded_target = ($dirs.target | path expand)

    let stow_file = compute-stow-path {
        path: $expanded_path,
        target: $expanded_target,
        source_dir: $dirs.source,
        package: $package
    }

    ensure-parent-dir $stow_file

    if ($path | path type) == 'symlink' {
        let link_target = (do -i { ^readlink $path })
        if $link_target != null {
            # Check if symlink target is already in the stow source directory
            if ($link_target | str starts-with $dirs.source) {
                log+ $"Already managed by stow: ($path)"
                return
            }
            ^ln -s $link_target $stow_file
        }
    } else {
        open --raw $path | save $stow_file
    }

    let target_link = compute-target-link $expanded_target $expanded_path
    ensure-parent-dir $target_link
    ^ln -sf $stow_file $target_link

    log+ $"Added: ($path) -> ($package)"
}

export def "main apply" [
    package: string,
    --target: string,
    --source-dir: string,
    --backup-dir: string
] {
    let dirs = (resolve-dirs $target $source_dir --backup-dir $backup_dir)

    if ($package | default-if-empty "" | is-empty) {
        error+ "package is required"
        return
    }

    let stow_pkg_dir = $dirs.source | path join $package

    if not ($stow_pkg_dir | path exists) {
        error+ $"Package does not exist: ($package)"
        return
    }

    let abs_stow_pkg = ($stow_pkg_dir | path expand)
    let abs_target = ($dirs.target | path expand)

    let files_to_link = collect-stow-files $abs_stow_pkg $abs_target

    for item in $files_to_link {
        let result = backup-file $item.target $abs_target $dirs.backup
        if not $result {
            error+ $"Failed to backup: ($item.target)"
            return
        }
    }

    link-files $files_to_link

    log+ $"Applied: ($package)"
}

def find-latest-backup [
    target_path: string,
    abs_target: string,
    abs_backup: string
] {
    let rel_target = ($target_path | path relative-to $abs_target)
    let backups = glob ($abs_backup | path join $"($rel_target)-*")
    | where { |b| ($b | path type) == 'file' }

    if ($backups | is-empty) {
        let type = (do -i { $target_path | path type } | default "none")
        if $type == 'file' {
            error make {
                msg: $"Cannot restore package: Target is a file but no backup found for ($target_path)"
                label: {
                    text: "Missing Backup"
                    span: (metadata $target_path).span
                }
            }
        } else {
            log+ $"Warning: No backup found for ($target_path)"
            return null
        }
    }

    # Sort by timestamp and get most recent
    let latest_backup = $backups
    | each { |b|
        let parsed_time = (
            $b | path basename | parse --regex '.*-(\d{8}_\d{6})$'
        )
        {
            path: $b,
            timestamp: (
                if ($parsed_time | is-empty) {
                    ""
                } else {
                    $parsed_time | get capture0 | first
                }
            )
        }
    }
    | where { |x| $x.timestamp != "" }
    | sort-by timestamp
    | last

    if $latest_backup == null {
        let type = (do -i { $target_path | path type } | default "none")
        if $type == 'file' {
            error make {
                msg: (
                    $"Cannot restore package: Target is a file but no valid "
                    + $"timestamp backup found for ($target_path)"
                )
                label: {
                    text: "Invalid Backup Data"
                    span: (metadata $target_path).span
                }
            }
        } else {
            log+ $"Warning: No valid timestamp backup found for ($target_path)"
            return null
        }
    }

    $latest_backup.path
}

def restore-file [target_path: string, backup_path: string] {
    # Remove current symlink/file
    let type = (do -i { $target_path | path type } | default "none")
    if $type in ['symlink', 'file'] {
        ^rm -f $target_path
    }

    # Restore from backup
    ensure-parent-dir $target_path
    ^cp $backup_path $target_path

    log+ $"Restored: ($target_path) <- ($backup_path)"
    true
}

# Best-effort restoration to decouple symlinked stows.
# Searches internal backup directories via timestamp sorting to find
# the newest copy of a managed file.
# If no valid backup exists but the target is a file, the pipeline fails loudly.
# Otherwise, it shows a warning and skips restoring that file.
export def "main restore" [
    package: string,
    --target: string,
    --source-dir: string,
    --backup-dir: string
] {
    let dirs = (resolve-dirs $target $source_dir --backup-dir $backup_dir)

    if ($package | default-if-empty "" | is-empty) {
        error+ "package is required"
        return
    }

    let stow_pkg_dir = $dirs.source | path join $package

    if not ($stow_pkg_dir | path exists) {
        error+ $"Package does not exist: ($package)"
        return
    }

    let abs_target = ($dirs.target | path expand)
    let abs_backup = ($dirs.backup | path expand)

    let files_to_link = collect-stow-files ($stow_pkg_dir | path expand) $abs_target
    mut restored_count = 0
    for item in $files_to_link {
        let latest_backup = (find-latest-backup $item.target $abs_target $abs_backup)
        if $latest_backup != null {
            let success = (restore-file $item.target $latest_backup)
            if $success {
                $restored_count += 1
            }
        }
    }

    if $restored_count > 0 {
        log+ $"Restored ($restored_count) file\(s\) for package: ($package)"
    } else {
        log+ $"No files restored for package: ($package)"
    }
}

export def "main help" [] {
    print "stow - Dotfiles manager

USAGE:
    stow add <package> <path>    Add file to stow package
    stow apply <package>        Apply stow package
    stow restore <package>      Restore from latest backup

OPTIONS:
    --target      Target directory (default: ~)
    --source-dir  Source directory (default: ~/.local/share/linux-config)
    --backup-dir  Backup directory for apply/restore (default: ~/.stow-backups)

EXAMPLES:
    stow add vim ~/.vimrc
    stow add nvim ~/.config/nvim/init.vim
    stow apply vim
    stow apply nvim --backup-dir ~/.backups
    stow restore vim
    stow restore nvim --backup-dir ~/.backups
"
}

def main [] {
    main help
}
