#!/usr/bin/env nu
# stow.nu requires running from bin/ directory or use: nu -I ./bin stow.nu

use ./lib.nu [
    try-relative
    ensure-parent-dir
    validate-path
    validate-file
    default-if-empty
    safe-ln
    safe-rm
    safe-cp
    safe-mkdir
]
use ./logs.nu [log+ error+]

def resolve-dirs [
    target: string = "",
    source_dir: string = "",
    --backup-dir: string = ""
] {
    let target_dir = ($target | default-if-empty $env.HOME)
    let source_dir = ($source_dir | default-if-empty ($target_dir | path join '.local' 'share' 'linux-config'))
    let backup_dir_out = ($backup_dir | default-if-empty ($target_dir | path join '.local' 'share' 'stow-backups'))
    { target: $target_dir, source: $source_dir, backup: $backup_dir_out }
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

def compute-stow-path [expanded_path: string, expanded_target: string, source_dir: string, package: string] {
    let relative_path = try-relative $expanded_path $expanded_target
    let stow_name = ($relative_path | path split | each { |p| to-stow-name $p })
    $source_dir | path join $package | path join ...$stow_name
}

def compute-target-link [expanded_target: string, expanded_path: string] {
    let relative_path = try-relative $expanded_path $expanded_target
    $expanded_target | path join $relative_path
}

def collect-stow-files [abs_stow_pkg: string, abs_target: string] {
    let glob_result = glob $"($abs_stow_pkg)/**/*"
    $glob_result
    | where { |item| ($item | path type) != 'dir' and $item != $abs_stow_pkg }
    | each { |item|
        let relative_path = try-relative $item $abs_stow_pkg
        let original_name = ($relative_path | path split | each { |p| from-stow-name $p })
        let target_path = $abs_target | path join ...$original_name
        { stow: $item, target: $target_path }
    }
}

def backup-file [file: string, abs_target: string, backup_dir: string] {
    let file_type = do -i { $file | path type } | default "none"
    if $file_type == 'symlink' {
        safe-rm $file
        true
    } else if $file_type == 'file' {
        if not ($backup_dir | path exists) {
            safe-mkdir $backup_dir
        }
        let timestamp = (date now | format date '%Y%m%d_%H%M%S')
        let expanded_path = ($file | path expand)
        let relative_path = try-relative $expanded_path $abs_target
        let backup_path = $backup_dir | path join $"($relative_path)-($timestamp)"
        ensure-parent-dir $backup_path
        safe-cp $file $backup_path
        safe-rm $file
    } else if $file_type == 'dir' {
        error make {
            msg: $"Destination is a directory, cannot replace with symlink: ($file)"
            label: { text: $file, span: (metadata $file).span }
        }
    } else {
        true
    }
}

def link-files [items: list<record<stow: string, target: string>>] {
    for item in $items {
        ensure-parent-dir $item.target
        safe-ln $item.stow $item.target
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
        validate-path $path --required
        validate-file $path
    } catch { |e|
        error+ $e.msg
        return
    }

    let expanded_path = ($path | path expand)
    let expanded_target = ($dirs.target | path expand)

    let stow_file = compute-stow-path $expanded_path $expanded_target $dirs.source $package

    ensure-parent-dir $stow_file

    if ($path | path type) == 'symlink' {
        let link_target = (do -i { ^readlink $path })
        if $link_target != null {
            # Check if the symlink target is already in the stow source directory
            if ($link_target | str starts-with $dirs.source) {
                log+ $"Already managed by stow: ($path)"
                return
            }
            ^ln -s $link_target $stow_file
        }
    } else {
        let content = open --raw $path
        $content | save $stow_file
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

    # Find all target files for this package
    let abs_stow_pkg = ($stow_pkg_dir | path expand)
    let files_to_restore = collect-stow-files $abs_stow_pkg $abs_target

    # Process each file and collect results
    let results = $files_to_restore
    | each { |item|
        let relative_path = try-relative $item.target $abs_target
        let backup_pattern = $abs_backup | path join $"($relative_path)-*"
        let backups = glob $backup_pattern
        | where { |b| ($b | path type) == 'file' }

        if ($backups | is-empty) {
            log+ $"No backup found for: ($item.target)"
            { restored: false }
        } else {
            # Sort by timestamp and get most recent
            let latest_backup = $backups
            | each { |b|
                let filename = $b | path basename
                let timestamp = $filename | parse --regex '.*-(\d{8}_\d{6})$' | get capture0 | default "" | first
                { path: $b, timestamp: $timestamp }
            }
            | where { |x| $x.timestamp != "" }
            | sort-by timestamp
            | last

            if $latest_backup == null {
                log+ $"No valid backup found for: ($item.target)"
                { restored: false }
            } else {
                # Remove current symlink/file
                let current_type = do -i { $item.target | path type } | default "none"
                if $current_type == 'symlink' {
                    safe-rm $item.target
                } else if $current_type == 'file' {
                    safe-rm $item.target
                }

                # Restore from backup
                ensure-parent-dir $item.target
                safe-cp $latest_backup.path $item.target

                log+ $"Restored: ($item.target) <- ($latest_backup.path)"
                { restored: true }
            }
        }
    }

    let restored_count = $results | where { |r| $r.restored } | length

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
    --backup-dir  Backup directory for apply/restore (default: ~/.local/share/stow-backups)

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
