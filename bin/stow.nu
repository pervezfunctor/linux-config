#!/usr/bin/env nu

# Stow: Add files/directories to stow with dot-prefix conversion
#
# Usage:
#   stow add <path> --target-dir <dir> --package <name> --stow-dir <dir>
#   stow apply <package> --target-dir <dir> --stow-dir <dir> --backup-dir <dir>
#
# Example:
#   stow add ~/.config/nvim --target-dir ~ --package nvim
#   stow apply nvim --target-dir ~

use std/log

def log+ [msg: string] { log info $msg }
def warn+ [msg: string] { log warning $msg }
def error+ [msg: string] { log error $msg }

# Convert a filename to stow-compatible format
# Converts leading dots in filenames to 'dot-' prefix
# Example: .vimrc -> dot-vimrc, .config -> dot-config
def to-stow-name [] {
    # If the name starts with a dot, replace it with 'dot-'
    let name = $in
    if ($name | str starts-with '.') {
        $"dot-($name | str substring 1..)"
    } else {
        # For other dots in the name, just return as-is
        # (stow handles internal dots fine, only leading dots are special)
        $name
    }
}

# Convert a stow name back to original filename
# Example: dot-vimrc -> .vimrc
def from-stow-name [] {
    let name = $in
    if ($name | str starts-with 'dot-') {
        $".($name | str substring 4..)"
    } else {
        $name
    }
}

# Recursively create stow-compatible directory structure
def create-stow-structure [
    source_path: string,  # Original source path (e.g., ~/.config/nvim)
    stow_pkg_dir: string, # Stow package directory (e.g., ~/.local/share/linux-config/nvim)
    target_dir: string,   # Target directory for symlinks (e.g., ~)
    current_path: string  # Current path being processed
] {
    let source_type = ($current_path | path type)

    if $source_type == 'dir' {
        # Expand and calculate relative path from target_dir
        let expanded_path = ($current_path | path expand)
        let expanded_target = ($target_dir | path expand)
        let relative_path = do -i {
            $expanded_path
            | path relative-to $expanded_target
        } | default $expanded_path

        # Build stow path by converting each component
        let converted_parts = $relative_path
            | path split
            | each { |part| $part | to-stow-name }
        let stow_path = $stow_pkg_dir | path join ...$converted_parts

        # Create the directory in stow package
        mkdir $stow_path

        # Recursively process directory contents
        if ($current_path | path exists) {
            for item in (ls -a $current_path | where name !~ '^\.\.?$') {
                create-stow-structure $source_path $stow_pkg_dir $target_dir $item.name
            }
        }
    } else if $source_type == 'file' {
        # Expand and calculate relative path from target_dir
        let expanded_path = ($current_path | path expand)
        let expanded_target = ($target_dir | path expand)
        let relative_path = do -i {
            $expanded_path
            | path relative-to $expanded_target
        } | default $expanded_path

        # Build stow path by converting each component
        let converted_parts = $relative_path
            | path split
            | each { |part| $part | to-stow-name }
        let stow_path = $stow_pkg_dir | path join ...$converted_parts

        # Create parent directory if needed
        let parent_dir = ($stow_path | path dirname)
        if not ($parent_dir | path exists) {
            mkdir $parent_dir
        }

        # Handle symlinks vs regular files
        if ($current_path | path type) == 'symlink' {
            let target = (do -i { ^readlink $current_path })
            if $target != null {
                ^ln -s $target $stow_path
            }
        } else {
            let content = open --raw $current_path
            $content | save $stow_path
        }
    }
}

# Main stow-add function
export def "main add" [
    path: string,              # Path to the file/directory to add (e.g., ~/.config/nvim)
    --target-dir: string,      # Target directory for symlinks (default: ~)
    --package: string,         # Package name (defaults to basename of path)
    --stow-dir: string         # Stow directory (default: ~/.local/share/linux-config)
] {
    # Set defaults
    let target_dir = if $target_dir == null or $target_dir == "" { $env.HOME } else { $target_dir }

    # Validate inputs
    if not ($path | path exists) {
        error+ $"Path does not exist: ($path)"
        return
    }

    # Determine package name
    let pkg_name = if $package == null {
        $path | path basename
    } else {
        $package
    }

    # Determine stow directory
    let stow_dir = if $stow_dir == null or $stow_dir == "" {
        $target_dir | path join '.local' 'share' 'linux-config'
    } else {
        $stow_dir
    }

    let stow_pkg_dir = $stow_dir | path join $pkg_name

    log+ $"Processing: ($path)"
    log+ $"Target: ($target_dir)"
    log+ $"Stow package: ($stow_pkg_dir)"

    # Create stow package directory
    if not ($stow_pkg_dir | path exists) {
        mkdir $stow_pkg_dir
    }

    # Create the stow-compatible structure
    create-stow-structure $path $stow_pkg_dir $target_dir $path

    # Run stow --adopt to link the files
    log+ $"Running stow --adopt for package: ($pkg_name)"

    let stow_result = do -i {
        ^stow --no-folding --adopt --dir $stow_dir --target $target_dir $pkg_name
    }

    if $env.LAST_EXIT_CODE == 0 {
        log+ $"Successfully stowed: ($pkg_name)"
    } else {
        warn+ "Stow command had issues"
    }
}

# Get list of files that a stow package would link
def get-stow-files [stow_pkg_dir: string, target_dir: string]: nothing -> list<string> {
    mut files = []

    # Walk through the stow package directory
    if ($stow_pkg_dir | path exists) {
        let abs_stow_pkg = ($stow_pkg_dir | path expand)
        let abs_target = ($target_dir | path expand)
        let pattern = $"($abs_stow_pkg)/**/*"
        for item in (glob $pattern) {
            # Skip directories and the stow package root itself
            if ($item | path type) == 'dir' or $item == $abs_stow_pkg {
                continue
            }

            let relative_path = do -i {
                $item
                | path relative-to $abs_stow_pkg
            } | default ($item | path basename)

            # Convert back from stow naming to original
            let converted_parts = $relative_path
                | path split
                | each { |part| $part | from-stow-name }
            let original_path = $abs_target | path join ...$converted_parts

            $files = ($files | append $original_path)
        }
    }

    $files
}

# Backup a file with timestamp (only files, not directories)
# Preserves directory structure relative to target_dir
def backup-path [path: string, backup_dir: string, target_dir: string] {
    if not ($path | path exists) {
        return
    }

    let path_type = ($path | path type)
    # Check if it's a file (not directory or symlink)
    if $path_type != 'file' {
        return
    }

    let timestamp = (date now | format date '%Y%m%d_%H%M%S')

    # Get relative path from target_dir to preserve structure
    let expanded_path = ($path | path expand)
    let expanded_target = ($target_dir | path expand)
    let relative_path = do -i {
        $expanded_path
        | path relative-to $expanded_target
    } | default ($path | path basename)

    let backup_path = $backup_dir | path join $"($relative_path)-($timestamp)"

    # Create backup directory structure if needed
    let backup_parent = ($backup_path | path dirname)
    if not ($backup_parent | path exists) {
        mkdir $backup_parent
    }

    log+ $"Backing up: ($path) -> ($backup_path)"

    # Copy file to backup, then remove original
    ^cp $path $backup_path
    ^rm -f $path
}

# Main stow-apply function
# Backs up existing files before applying stow package
export def "main apply" [
    package: string,           # Package name to apply (e.g., nvim)
    --target-dir: string,      # Target directory for symlinks (default: ~)
    --stow-dir: string,        # Stow directory (default: ~/.local/share/linux-config)
    --backup-dir: string       # Backup directory (default: ~/.local/share/stow-backups)
] {
    # Set defaults
    let target_dir = if $target_dir == null or $target_dir == "" { $env.HOME } else { $target_dir }
    let stow_dir = if $stow_dir == null or $stow_dir == "" {
        $target_dir | path join '.local' 'share' 'linux-config'
    } else {
        $stow_dir
    }
    let backup_dir = if $backup_dir == null or $backup_dir == "" {
        $target_dir | path join '.local' 'share' 'stow-backups'
    } else {
        $backup_dir
    }

    let stow_pkg_dir = $stow_dir | path join $package

    # Validate package exists
    if not ($stow_pkg_dir | path exists) {
        error+ $"Stow package does not exist: ($stow_pkg_dir)"
        return
    }

    log+ $"Applying stow package: ($package)"
    log+ $"Target: ($target_dir)"
    log+ $"Backup dir: ($backup_dir)"

    # Get list of files that stow would link
    let files_to_link = get-stow-files $stow_pkg_dir $target_dir

    if ($files_to_link | is-empty) {
        warn+ $"No files found in package: ($package)"
    }

    # Backup existing files and remove unmanaged symlinks
    for file in $files_to_link {
        # Check path type regardless of whether target exists
        let file_type = do -i { $file | path type } | default "none"
        
        if $file_type == 'symlink' {
            log+ $"Removing unmanaged symlink: ($file)"
            ^rm -f $file
        } else if $file_type == 'file' {
            backup-path $file $backup_dir $target_dir
        }
    }

    # Run stow to apply the package
    log+ $"Running stow for package: ($package)"

    do -i {
        ^stow --no-folding --dir $stow_dir --target $target_dir $package
    }

    if $env.LAST_EXIT_CODE == 0 {
        log+ $"Successfully applied stow package: ($package)"
    } else {
        error+ "Stow failed"
        return
    }

    # Show backup info if any backups were made
    let backup_files = do -i { ls $backup_dir }
    if $env.LAST_EXIT_CODE == 0 and not ($backup_files | is-empty) {
        log+ $"Backups stored in: ($backup_dir)"
        log+ $"Total backups: (($backup_files | length))"
    }
}

export def "main help" [] {
    print "stow - GNU Stow wrapper for managing dotfiles

USAGE:
    stow add <path> [options]       Add files to stow package
    stow apply <package> [options]  Apply stow package with backups
    stow help                       Show this help

COMMANDS:
    add            Convert existing files/directories to stow package
    apply          Apply stow package with automatic backup of conflicts
    help           Show this help message

OPTIONS FOR 'stow add':
    --target-dir   Target directory for symlinks (default: ~)
    --package      Package name (default: basename of path)
    --stow-dir     Stow directory (default: ~/.local/share/linux-config)

OPTIONS FOR 'stow apply':
    --target-dir   Target directory for symlinks (default: ~)
    --stow-dir     Stow directory (default: ~/.local/share/linux-config)
    --backup-dir   Backup directory (default: ~/.local/share/stow-backups)

EXAMPLES:
    stow add ~/.vimrc --package vim
    stow add ~/.config/nvim --target-dir ~ --package nvim
    stow apply vim
    stow apply nvim --backup-dir ~/.backups

NAMING CONVENTION:
    .vimrc      -> dot-vimrc
    .config/nvim -> dot-config/nvim
    normal-file -> normal-file (unchanged)
"
}

# Main entry point for script execution
def main [] {
    let args = $env.ARGS
    if ($args | is-empty) or ($args.0 == "help") {
        main help
    } else {
        main help
    }
}
