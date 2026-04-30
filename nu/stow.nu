#!/usr/bin/env nu

use ./lib.nu *

# Resolves target, source, and backup directories to their final absolute
# or default paths. If no custom paths are provided, defaults to $env.HOME
# and its .local/share subdirectories.
#
# Example:
#   resolve-dirs --target "/opt"
#   # => {
#   #   target: "/opt",
#   #   source: "/home/user/.linux-config",
#   #   backup: "/home/user/.stow-backups"
#   # }
def resolve-dirs [
    target: string = "",
    source_dir: string = "",
    --backup-dir: string = ""
] {
    {
        target: ($target | or-else $env.HOME)
        source: (
            $source_dir
            | or-else (
                $env.HOME
                | path join '.local' 'share' 'linux-config'
            )
        )
        backup: (
            $backup_dir
            | or-else ($env.HOME | path join '.stow-backups')
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

def fail [msg: string] {
    error+ $msg
    error make { msg: $msg }
}

# Creates a labeled Nushell error bound to a concrete filesystem path so
# callers can reuse consistent diagnostics without losing span information.
def fail-path [msg: string, path: string, label_text: string = ""] {
    error make {
        msg: $msg
        label: {
            text: ($label_text | or-else $path)
            span: (metadata $path).span
        }
    }
}

def relative-to-target [path: string, target: string] {
    try {
        $path | path relative-to $target
    } catch {
        fail-path (
            $"Path ($path) is outside the target "
            + $"directory ($target)"
        ) $path
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
    $ctx.source_dir
    | path join $ctx.package
    | path join ...(
        relative-to-target $ctx.path $ctx.target
        | path split
        | each { |p| to-stow-name $p }
    )
}

# Calculates the final symlink exact destination inside the target
# deployment boundary.
#
# Example:
#   compute-target-link "/home/user" "/home/user/.config/nvim/init.lua"
#   # => "/home/user/.config/nvim/init.lua"
def compute-target-link [expanded_target: string, expanded_path: string] {
    $expanded_target | path join (relative-to-target $expanded_path $expanded_target)
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
# If a pre-existing target file is a real file, it is timestamped, copied to a
# package-specific path under `backup_dir`, and then destroyed.
# Backups are also scoped by the expanded target root so the same package can be
# applied to multiple target directories without sharing backup files.
#
# Example:
#   backup-file "/home/user/.bashrc" "/home/user" "/home/user/backups" "shell"
#   # Backs up the real file to
#   # "/home/user/backups/shell/_root_/home/user/.bashrc-20230501_120000"
#   # and deletes original file.
def backup-scope-dir [backup_dir: string, package: string, abs_target: string] {
    let target_segments = (
        $abs_target
        | path expand
        | path split
        | each { |segment|
            if $segment in ['', '/'] {
                '_root_'
            } else {
                to-stow-name $segment
            }
        }
    )

    $backup_dir | path join $package | path join ...$target_segments
}

def backup-path [package_backup_dir: string, rel_path: string, timestamp: string] {
    $package_backup_dir | path join $"($rel_path)-($timestamp)"
}

def backup-file [file: string, abs_target: string, backup_dir: string, package: string] {
    let file_type = do -i { $file | path type } | default "none"
    let package_backup_dir = (backup-scope-dir $backup_dir $package $abs_target)

    if $file_type == 'symlink' {
        ^rm -f $file
    } else if $file_type == 'file' {
        if not ($package_backup_dir | path exists) {
            mkdir $package_backup_dir
        }
        let timestamp = (date now | format date '%Y%m%d_%H%M%S')
        let rel_path = (relative-to-target ($file | path expand) $abs_target)
        let backup_path = (backup-path $package_backup_dir $rel_path $timestamp)
        if ($backup_path | path exists) {
            fail-path (
                $"Backup path already exists for timestamp collision: ($backup_path)"
            ) $backup_path "Backup Timestamp Collision"
        }
        ensure-parent-dir $backup_path
        ^cp -p $file $backup_path
        ^rm -f $file
    } else if $file_type == 'dir' {
        fail-path (
            $"Destination is a directory, cannot "
            + $"replace with symlink: ($file)"
        ) $file
    }
}

def link-files [items: list<record<stow: string, target: string>>] {
    for item in $items {
        ensure-parent-dir $item.target
        ^ln -sf $item.stow $item.target
    }
}

# Preflight guard used by apply/restore planning so a package fails before any
# mutation if one of its targets is blocked by a real directory.
def ensure-target-not-directory [target_path: string, operation: string] {
    if (target-path-type $target_path) == 'dir' {
        fail-path $"Destination is a directory, cannot ($operation): ($target_path)" $target_path
    }
}

# Validates every apply destination before backup-file or link-files mutate the
# target tree. Returning the original items keeps execution logic simple.
def plan-apply-ops [items: list<record<stow: string, target: string>>] {
    $items | each { |item|
        ensure-target-not-directory $item.target "replace with symlink"
        $item
    }
}

export def "main add" [
    package: string,
    path: string,
    --target: string,
    --source-dir: string
] {
    let dirs = (resolve-dirs $target $source_dir)
    let expanded_source = ($dirs.source | path expand)

    if ($package | or-else "" | is-empty) {
        fail "package is required"
    }

    check-file $path
    let expanded_path = ($path | path expand)
    let expanded_target = ($dirs.target | path expand)

    let stow_file = compute-stow-path {
        path: $expanded_path,
        target: $expanded_target,
        source_dir: $expanded_source,
        package: $package
    }

    ensure-parent-dir $stow_file
    ^cp -p -f $path $stow_file

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

    if ($package | or-else "" | is-empty) {
        fail "package is required"
    }

    let stow_pkg_dir = $dirs.source | path join $package

    if not ($stow_pkg_dir | path exists) {
        fail $"Package does not exist: ($package)"
    }

    let abs_stow_pkg = ($stow_pkg_dir | path expand)
    let abs_target = ($dirs.target | path expand)
    let abs_backup = ($dirs.backup | path expand)

    let files_to_link = collect-stow-files $abs_stow_pkg $abs_target
    let apply_plan = (plan-apply-ops $files_to_link)

    for item in $apply_plan {
        backup-file $item.target $abs_target $abs_backup $package
    }

    link-files $apply_plan

    log+ $"Applied: ($package)"
}

def target-path-type [target_path: string] {
    do -i { $target_path | path type } | default "none"
}

def readlink-target [path: string] {
    do -i { ^readlink $path } | default ""
}

def parse-backup-candidate [backup_path: string, prefix: string] {
    let basename = ($backup_path | path basename)
    let suffix = ($basename | str substring ($prefix | str length)..)
    {
        path: $backup_path,
        timestamp: (if $suffix =~ '^[0-9]{8}_[0-9]{6}$' { $suffix } else { "" })
    }
}

def backup-lookup [
    target_path: string,
    abs_target: string,
    abs_backup: string,
    package: string
] {
    let rel_target = (relative-to-target $target_path $abs_target)
    let backup_parent = (
        backup-scope-dir $abs_backup $package $abs_target
        | path join ($rel_target | path dirname)
    )
    let prefix = $"(($rel_target | path basename))-"
    let candidates = (
        do -i { ls -a $backup_parent | get name }
        | default []
        | where { |b| (($b | path type) == 'file') and ((($b | path basename) | str starts-with $prefix)) }
        | each { |b| parse-backup-candidate $b $prefix }
    )

    if ($candidates | is-empty) {
        return {
            status: 'missing'
            path: null
        }
    }

    let latest_backup = (
        $candidates
        | where { |x| $x.timestamp != "" }
        | sort-by timestamp
        | last
    )
    if $latest_backup == null {
        return {
            status: 'invalid'
            path: null
        }
    }

    {
        status: 'found'
        path: $latest_backup.path
    }
}

def classify-target [target_path: string, stow_path: string = ""] {
    let type = (target-path-type $target_path)

    if $type == 'none' {
        return {
            state: 'missing'
            link_target: ''
        }
    }

    if $type == 'dir' {
        return {
            state: 'directory'
            link_target: ''
        }
    }

    if $type == 'file' {
        return {
            state: 'file'
            link_target: ''
        }
    }

    let link_target = (readlink-target $target_path)
    {
        state: (
            if ($stow_path != "") and ($link_target == $stow_path) {
                'managed'
            } else {
                'foreign-symlink'
            }
        )
        link_target: $link_target
    }
}

# Builds the full remove action list up front so remove either validates the
# whole package or leaves the target tree untouched. The returned records carry
# both target ownership state and any restorable backup chosen for that path.
def plan-remove-ops [
    items: list<record<stow: string, target: string>>
    abs_target: string
    abs_backup: string
    package: string
] {
    $items | each { |item|
        let target_state = (removable-target-state $item.target $item.stow)
        let lookup = (backup-lookup $item.target $abs_target $abs_backup $package)

        if $lookup.status == 'invalid' {
            fail-path (
                $"Cannot remove package: Invalid timestamp backup found for ($item.target)"
            ) $item.target "Invalid Backup Data"
        }

        {
            target: $item.target
            target_state: $target_state
            backup_status: $lookup.status
            backup_path: $lookup.path
        }
    }
}

# Precomputes every restore decision before restore-file runs so a later
# directory collision or file-without-backup error cannot partially restore an
# earlier target.
def plan-restore-ops [
    items: list<record<stow: string, target: string>>
    abs_target: string
    abs_backup: string
    package: string
] {
    $items | each { |item|
        ensure-target-not-directory $item.target "restore file"
        let lookup = (backup-lookup $item.target $abs_target $abs_backup $package)
        let target_state = (classify-target $item.target)

        if $lookup.status == 'missing' {
            if $target_state.state == 'file' {
                fail-path (
                    $"Cannot restore package: Target is a file but no backup found for ($item.target)"
                ) $item.target "Missing Backup"
            }

            return {
                target: $item.target
                backup_path: null
                warning: $"Warning: No backup found for ($item.target)"
            }
        }

        if $lookup.status == 'invalid' {
            if $target_state.state == 'file' {
                fail-path (
                    $"Cannot restore package: Target is a file but no valid "
                    + $"timestamp backup found for ($item.target)"
                ) $item.target "Invalid Backup Data"
            }

            return {
                target: $item.target
                backup_path: null
                warning: $"Warning: No valid timestamp backup found for ($item.target)"
            }
        }

        {
            target: $item.target
            backup_path: $lookup.path
            warning: ""
        }
    }
}

def removable-target-state [target_path: string, stow_path: string] {
    let target = (classify-target $target_path $stow_path)

    if $target.state == 'missing' {
        return 'missing'
    }

    if $target.state == 'directory' {
        fail-path (
            $"Destination is a directory, cannot remove package target: ($target_path)"
        ) $target_path
    }

    if $target.state != 'managed' {
        fail-path $"Target is not the managed symlink for package: ($target_path)" $target_path
    }

    'managed'
}

def current-target-status [target_path: string, stow_path: string] {
    classify-target $target_path $stow_path
}

def package-status-records [
    stow_pkg_dir: string,
    abs_target: string,
    abs_backup: string,
    package: string
] {
    collect-stow-files ($stow_pkg_dir | path expand) $abs_target
    | each { |item|
        let target_state = (current-target-status $item.target $item.stow)
        let backup = (backup-lookup $item.target $abs_target $abs_backup $package)

        {
            target: $item.target
            stow: $item.stow
            state: $target_state.state
            link_target: $target_state.link_target
            backup_status: $backup.status
            backup_path: (if $backup.path == null { '' } else { $backup.path })
        }
    }
}

def restore-file [target_path: string, backup_path: string] {
    # Remove current symlink/file
    let type = (target-path-type $target_path)
    if $type in ['symlink', 'file'] {
        ^rm -f $target_path
    } else if $type == 'dir' {
        fail-path $"Destination is a directory, cannot restore file: ($target_path)" $target_path
    }

    # Restore from backup
    ensure-parent-dir $target_path
    ^cp -p $backup_path $target_path

    log+ $"Restored: ($target_path) <- ($backup_path)"
}

export def "main remove" [
    package: string,
    --target: string,
    --source-dir: string,
    --backup-dir: string
] {
    let dirs = (resolve-dirs $target $source_dir --backup-dir $backup_dir)

    if ($package | or-else "" | is-empty) {
        fail "package is required"
    }

    let stow_pkg_dir = $dirs.source | path join $package

    if not ($stow_pkg_dir | path exists) {
        fail $"Package does not exist: ($package)"
    }

    let abs_target = ($dirs.target | path expand)
    let abs_backup = ($dirs.backup | path expand)
    let files_to_link = collect-stow-files ($stow_pkg_dir | path expand) $abs_target
    let remove_plan = (plan-remove-ops $files_to_link $abs_target $abs_backup $package)

    mut removed_count = 0
    mut restored_count = 0
    for item in $remove_plan {
        if $item.target_state == 'managed' {
            ^rm -f $item.target
            $removed_count += 1
        }

        if $item.backup_status == 'found' {
            restore-file $item.target $item.backup_path
            $restored_count += 1
        }
    }

    if $restored_count > 0 or $removed_count > 0 {
        log+ $"Removed package: ($package) \(restored ($restored_count) file\(s\), removed ($removed_count) managed link\(s\)\)"
    } else {
        log+ $"No files removed for package: ($package)"
    }
}

export def "main status" [
    package: string,
    --target: string,
    --source-dir: string,
    --backup-dir: string
] {
    let dirs = (resolve-dirs $target $source_dir --backup-dir $backup_dir)

    if ($package | or-else "" | is-empty) {
        fail "package is required"
    }

    let stow_pkg_dir = $dirs.source | path join $package

    if not ($stow_pkg_dir | path exists) {
        fail $"Package does not exist: ($package)"
    }

    let abs_target = ($dirs.target | path expand)
    let abs_backup = ($dirs.backup | path expand)

    package-status-records $stow_pkg_dir $abs_target $abs_backup $package
}

export def "main doctor" [
    package: string,
    --target: string,
    --source-dir: string,
    --backup-dir: string
] {
    let dirs = (resolve-dirs $target $source_dir --backup-dir $backup_dir)

    if ($package | or-else "" | is-empty) {
        fail "package is required"
    }

    let stow_pkg_dir = $dirs.source | path join $package

    if not ($stow_pkg_dir | path exists) {
        fail $"Package does not exist: ($package)"
    }

    let abs_target = ($dirs.target | path expand)
    let abs_backup = ($dirs.backup | path expand)
    let records = (package-status-records $stow_pkg_dir $abs_target $abs_backup $package)
    let issues = (
        $records
        | where { |row| $row.state != 'managed' or $row.backup_status == 'invalid' }
    )

    if ($issues | is-empty) {
        return $records
    }

    print $issues
    fail $"Doctor found (($issues | length)) issue\(s\) for package: ($package)"
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

    if ($package | or-else "" | is-empty) {
        fail "package is required"
    }

    let stow_pkg_dir = $dirs.source | path join $package

    if not ($stow_pkg_dir | path exists) {
        fail $"Package does not exist: ($package)"
    }

    let abs_target = ($dirs.target | path expand)
    let abs_backup = ($dirs.backup | path expand)

    let files_to_link = collect-stow-files ($stow_pkg_dir | path expand) $abs_target
    let restore_plan = (plan-restore-ops $files_to_link $abs_target $abs_backup $package)

    for item in $restore_plan {
        if not ($item.warning | is-empty) {
            log+ $item.warning
        }
    }

    mut restored_count = 0
    for item in $restore_plan {
        if $item.backup_path != null {
            restore-file $item.target $item.backup_path
            $restored_count += 1
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
    stow add <package> <path> [--target <dir>] [--source-dir <dir>]
    stow apply <package> [--target <dir>] [--source-dir <dir>] [--backup-dir <dir>]
    stow remove <package> [--target <dir>] [--source-dir <dir>] [--backup-dir <dir>]
    stow status <package> [--target <dir>] [--source-dir <dir>] [--backup-dir <dir>]
    stow doctor <package> [--target <dir>] [--source-dir <dir>] [--backup-dir <dir>]
    stow restore <package> [--target <dir>] [--source-dir <dir>] [--backup-dir <dir>]

OPTIONS:
    --target      Target directory (default: ~)
    --source-dir  Source directory (default: ~/.linux-config)
    --backup-dir  Backup directory for apply/remove/status/doctor/restore (default: ~/.stow-backups)

EXAMPLES:
    stow add vim ~/.vimrc
    stow add nvim ~/.config/nvim/init.vim
    stow apply vim
    stow apply nvim --backup-dir ~/.backups
    stow remove vim
    stow remove nvim --backup-dir ~/.backups
    stow status vim
    stow doctor vim --backup-dir ~/.backups
    stow restore vim
    stow restore nvim --backup-dir ~/.backups
"
}

def main [] {
    main help
}
