#!/usr/bin/env nu

# Stow: Add files to stow with dot-prefix conversion
#
# Usage:
#   stow add <package> <path>
#   stow apply <package> [--target <dir>] [--source-dir <dir>] [--backup-dir <dir>]
#
# Example:
#   stow add vim ~/.vimrc
#   stow add nvim ~/.config/nvim/init.vim
#   stow apply vim
#   stow apply nvim --backup-dir ~/.backups

use std/log

def log+ [msg: string] { log info $msg }
def warn+ [msg: string] { log warning $msg }
def error+ [msg: string] { log error $msg }

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

def ensure-parent-dir [path: string] {
    let parent = ($path | path dirname)
    if not ($parent | path exists) {
        mkdir $parent
    }
}

export def "main add" [
    package: string,
    path: string,
    --target: string,
    --source-dir: string
] {
    let target_dir = if $target == null or $target == "" { $env.HOME } else { $target }
    let source_dir = if $source_dir == null or $source_dir == "" {
        $target_dir | path join '.local' 'share' 'linux-config'
    } else {
        $source_dir
    }

    if $path == "" or $path == null {
        error+ "path is required"
        return
    }

    if $package == "" or $package == null {
        error+ "package is required"
        return
    }

    if not ($path | path exists) {
        error+ $"Path does not exist: ($path)"
        return
    }

    if ($path | path type) != 'file' {
        error+ $"Not a file: ($path)"
        return
    }

    let expanded_path = ($path | path expand)
    let expanded_target = ($target_dir | path expand)

    let relative_path = do -i {
        $expanded_path
        | path relative-to $expanded_target
    } | default ($expanded_path | path basename)

    let stow_name = ($relative_path | path split | each { |p| to-stow-name $p })
    let stow_file = $source_dir | path join $package | path join ...$stow_name

    ensure-parent-dir $stow_file

    if ($path | path type) == 'symlink' {
        let link_target = (do -i { ^readlink $path })
        if $link_target != null {
            ^ln -s $link_target $stow_file
        }
    } else {
        let content = open --raw $path
        $content | save $stow_file
    }

    let target_link = $expanded_target | path join $relative_path
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
    let target_dir = if $target == null or $target == "" { $env.HOME } else { $target }
    let source_dir = if $source_dir == null or $source_dir == "" {
        $target_dir | path join '.local' 'share' 'linux-config'
    } else {
        $source_dir
    }
    let backup_dir = if $backup_dir == null or $backup_dir == "" {
        $target_dir | path join '.local' 'share' 'stow-backups'
    } else {
        $backup_dir
    }

    if $package == "" or $package == null {
        error+ "package is required"
        return
    }

    let stow_pkg_dir = $source_dir | path join $package

    if not ($stow_pkg_dir | path exists) {
        error+ $"Package does not exist: ($package)"
        return
    }

    let abs_stow_pkg = ($stow_pkg_dir | path expand)
    let abs_target = ($target_dir | path expand)

    mut files_to_link = []
    for item in (glob $"($abs_stow_pkg)/**/*") {
        if ($item | path type) == 'dir' or $item == $abs_stow_pkg {
            continue
        }

        let relative_path = do -i {
            $item
            | path relative-to $abs_stow_pkg
        } | default ($item | path basename)

        let original_name = ($relative_path | path split | each { |p| from-stow-name $p })
        let target_path = $abs_target | path join ...$original_name

        $files_to_link = ($files_to_link | append { stow: $item, target: $target_path })
    }

    for item in $files_to_link {
        let file = $item.target
        let file_type = do -i { $file | path type } | default "none"

        if $file_type == 'symlink' {
            ^rm -f $file
        } else if $file_type == 'file' {
            if not ($backup_dir | path exists) {
                mkdir $backup_dir
            }

            let timestamp = (date now | format date '%Y%m%d_%H%M%S')
            let expanded_path = ($file | path expand)
            let relative_path = do -i {
                $expanded_path
                | path relative-to $abs_target
            } | default ($file | path basename)

            let backup_path = $backup_dir | path join $"($relative_path)-($timestamp)"
            ensure-parent-dir $backup_path

            ^cp $file $backup_path
            ^rm -f $file
        } else if $file_type == 'dir' {
            error+ $"Destination is a directory, cannot replace with symlink: ($file)"
            return
        }
    }

    for item in $files_to_link {
        ensure-parent-dir $item.target
        ^ln -sf $item.stow $item.target
    }

    log+ $"Applied: ($package)"
}

export def "main help" [] {
    print "stow - Dotfiles manager

USAGE:
    stow add <package> <path>    Add file to stow package
    stow apply <package>        Apply stow package

OPTIONS:
    --target      Target directory (default: ~)
    --source-dir  Source directory (default: ~/.local/share/linux-config)
    --backup-dir  Backup directory for apply (default: ~/.local/share/stow-backups)

EXAMPLES:
    stow add vim ~/.vimrc
    stow add nvim ~/.config/nvim/init.vim
    stow apply vim
    stow apply nvim --backup-dir ~/.backups
"
}

def main [] {
    main help
}
