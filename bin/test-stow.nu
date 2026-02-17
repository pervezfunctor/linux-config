#!/usr/bin/env nu

# Test script for stow and stow apply functions
# This creates a temporary test environment and validates both functions

use std/log

def log+ [msg: string] { log info $msg }
def warn+ [msg: string] { log warning $msg }
def error+ [msg: string] { log error $msg }

# Create temporary test directory
let timestamp = (date now | format date "%Y%m%d_%H%M%S")
let test_base = $env.TMPDIR? | default "/tmp" | path join $"stow-test-($timestamp)"
mkdir $test_base
let source_dir = $test_base | path join "source"
let target_dir = $test_base | path join "target"
let stow_dir = $test_base | path join "stow"
let backup_dir = $test_base | path join "backups"
let target2_dir = $test_base | path join "target2"

log+ $"Test directory: ($test_base)"

# Create test directory structure
mkdir $source_dir
mkdir $target_dir
mkdir $stow_dir

# Create source files with dot prefixes
mkdir $"($source_dir)/.config/nvim/lua"
mkdir $"($source_dir)/.config/kitty"
mkdir $"($source_dir)/.vim"

"nvim config" | save $"($source_dir)/.config/nvim/init.vim"
"lua options" | save $"($source_dir)/.config/nvim/lua/options.lua"
"kitty config" | save $"($source_dir)/.config/kitty/kitty.conf"
"vimrc content" | save $"($source_dir)/.vimrc"
"gitconfig" | save $"($source_dir)/.gitconfig"

# ==============================================================================
# Helper functions
# ==============================================================================

def to-stow-name [] {
    let name = $in
    if ($name | str starts-with '.') {
        $"dot-($name | str substring 1..)"
    } else {
        $name
    }
}

def from-stow-name [] {
    let name = $in
    if ($name | str starts-with 'dot-') {
        $".($name | str substring 4..)"
    } else {
        $name
    }
}

def create-stow-structure [
    source_path: string,
    stow_pkg_dir: string,
    target_dir: string,
    current_path: string
] {
    let source_type = ($current_path | path type)

    if $source_type == 'dir' {
        let relative_path = do -i {
            $current_path
            | path relative-to $target_dir
        } | default $current_path

        let converted_parts = $relative_path
            | path split
            | each { |part| $part | to-stow-name }
        let stow_path = $stow_pkg_dir | path join ...$converted_parts

        mkdir $stow_path

        if ($current_path | path exists) {
            for item in (ls -a $current_path | where name !~ '^\.\.?$') {
                create-stow-structure $source_path $stow_pkg_dir $target_dir $item.name
            }
        }
    } else if $source_type == 'file' {
        let relative_path = do -i {
            $current_path
            | path relative-to $target_dir
        } | default $current_path

        let converted_parts = $relative_path
            | path split
            | each { |part| $part | to-stow-name }
        let stow_path = $stow_pkg_dir | path join ...$converted_parts

        let parent_dir = ($stow_path | path dirname)
        if not ($parent_dir | path exists) {
            mkdir $parent_dir
        }

        # Copy the file content to stow package
        let content = open --raw $current_path
        $content | save $stow_path
    }
}

def stow-add-func [
    path: string,
    target_dir: string,
    package: string,
    stow_dir: string
] {
    if not ($path | path exists) {
        error+ $"Path does not exist: ($path)"
        return
    }

    let stow_pkg_dir = $stow_dir | path join $package

    log+ $"Processing: ($path)"
    log+ $"Target: ($target_dir)"
    log+ $"Stow package: ($stow_pkg_dir)"

    if not ($stow_pkg_dir | path exists) {
        mkdir $stow_pkg_dir
    }

    create-stow-structure $path $stow_pkg_dir $target_dir $path

    log+ $"Running stow --adopt for package: ($package)"

    do -i {
        ^stow --no-folding --adopt --dir $stow_dir --target $target_dir $package
    }

    if $env.LAST_EXIT_CODE == 0 {
        log+ $"Successfully stowed: ($package)"
    } else {
        warn+ "Stow command had issues"
    }
}

def get-stow-files [stow_pkg_dir: string, target_dir: string]: nothing -> list<string> {
    mut files = []

    if ($stow_pkg_dir | path exists) {
        let pattern = $"($stow_pkg_dir)/**/*"
        for item in (glob $pattern) {
            # Skip directories and the stow package root itself
            if ($item | path type) == 'dir' or $item == $stow_pkg_dir {
                continue
            }

            let relative_path = do -i {
                $item
                | path relative-to $stow_pkg_dir
            } | default ($item | path basename)

            # Convert back from stow naming to original
            let converted_parts = $relative_path
                | path split
                | each { |part| $part | from-stow-name }
            let original_path = $target_dir | path join ...$converted_parts

            $files = ($files | append $original_path)
        }
    }

    $files
}

def backup-path [path: string, backup_dir: string, target_dir: string] {
    if not ($path | path exists) {
        return
    }

    # Check if it's a file (not directory)
    if ($path | path type) != 'file' {
        return
    }

    let timestamp = (date now | format date '%Y%m%d_%H%M%S')
    
    # Get relative path from target_dir to preserve structure
    let relative_path = do -i {
        $path | path relative-to $target_dir
    } | default ($path | path basename)
    
    let backup_path = $backup_dir | path join $"($relative_path)-($timestamp)"

    let backup_parent = ($backup_path | path dirname)
    if not ($backup_parent | path exists) {
        mkdir $backup_parent
    }

    log+ $"Backing up: ($path) -> ($backup_path)"
    ^cp $path $backup_path
    ^rm -f $path
}

def stow-apply-func [
    package: string,
    target_dir: string,
    stow_dir: string,
    backup_dir: string
] {
    let stow_pkg_dir = $stow_dir | path join $package

    if not ($stow_pkg_dir | path exists) {
        error+ $"Stow package does not exist: ($stow_pkg_dir)"
        return
    }

    log+ $"Applying stow package: ($package)"
    log+ $"Target: ($target_dir)"
    log+ $"Backup dir: ($backup_dir)"

    let files_to_link = get-stow-files $stow_pkg_dir $target_dir

    if ($files_to_link | is-empty) {
        warn+ $"No files found in package: ($package)"
    }

    # Backup existing files
    for file in $files_to_link {
        if ($file | path exists) {
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

# ==============================================================================
# TESTS
# ==============================================================================

def test-result [test_name: string, passed: bool, detail: string] {
    let status = if $passed { "[PASS]" } else { "[FAIL]" }
    print $"($status) ($test_name)"
    if not $passed {
        print $"  Detail: ($detail)"
    }
}

# Test 1: Copy source to target and run stow-add
log+ "=== Test 1: stow-add function ==="
mkdir $"($target_dir)/.config"
^cp -r $"($source_dir)/.config/nvim" $"($target_dir)/.config/"
stow-add-func $"($target_dir)/.config/nvim" $target_dir "nvim" $stow_dir

# Verify stow package was created correctly
let stow_files = glob $"($stow_dir)/nvim/**/*" | where {|it| ($it | path type) == "file" }
let expected_files = [
    $"($stow_dir)/nvim/dot-config/nvim/init.vim",
    $"($stow_dir)/nvim/dot-config/nvim/lua/options.lua"
]

test-result "stow-add creates correct structure" (
    ($stow_files | length) == 2 and
    ($stow_dir | path join "nvim/dot-config/nvim/init.vim" | path exists) and
    ($stow_dir | path join "nvim/dot-config/nvim/lua/options.lua" | path exists)
) $"Found ($stow_files | length) files, expected 2"

# Verify symlinks were created
let init_vim_is_symlink = ($target_dir | path join ".config/nvim/init.vim" | path type) == "symlink"
test-result "stow-add creates symlinks" $init_vim_is_symlink "init.vim should be a symlink"

# Verify file content is preserved
let content = open ($target_dir | path join ".config/nvim/init.vim")
test-result "stow-add preserves file content" ($content == "nvim config") $"Content: ($content)"

# Test 2: stow-apply with backups
log+ ""
log+ "=== Test 2: stow-apply function ==="

# Create target2 with conflicting files
mkdir $"($target2_dir)/.config/nvim"
"OLD CONTENT" | save $"($target2_dir)/.config/nvim/init.vim"

stow-apply-func "nvim" $target2_dir $stow_dir $backup_dir

# Verify backup was created with path structure preserved
let backup_files = glob $"($backup_dir)/**/*" | where {|it| ($it | path type) == "file" }
let backup_exists = ($backup_files | length) > 0
test-result "stow-apply creates backups" $backup_exists "Should have backed up conflicting file"

# Verify backup preserves path structure
let backup_has_path = ($backup_files | any {|f| $f | str contains ".config/nvim"})
test-result "backup preserves path structure" $backup_has_path "Backup should include .config/nvim path"

# Verify symlink was created
let symlink_exists = ($target2_dir | path join ".config/nvim/init.vim" | path type) == "symlink"
test-result "stow-apply creates symlinks after backup" $symlink_exists "Should have created symlink"

# Verify backup has old content
let backup_content = if ($backup_files | length) > 0 { open ($backup_files | first) } else { "" }
test-result "stow-apply preserves old content in backup" (
    $backup_content == "OLD CONTENT"
) $"Backup content: ($backup_content)"

# Test 3: get-stow-files returns correct paths
log+ ""
log+ "=== Test 3: get-stow-files function ==="

let files = get-stow-files ($stow_dir | path join "nvim") $target_dir
log+ $"Files returned: ($files)"
test-result "get-stow-files returns correct count" (
    ($files | length) == 2
) $"Found ($files | length) files, expected 2"

let has_init_vim = ($files | any {|f| $f | str ends-with ".config/nvim/init.vim"})
test-result "get-stow-files returns correct paths" $has_init_vim "Should include .config/nvim/init.vim"

# Test 4: to-stow-name and from-stow-name conversions
log+ ""
log+ "=== Test 4: name conversion functions ==="

let to_result = ".config" | to-stow-name
test-result "to-stow-name converts dots" ($to_result == "dot-config") $"Got: ($to_result)"

let from_result = "dot-config" | from-stow-name
test-result "from-stow-name converts back" ($from_result == ".config") $"Got: ($from_result)"

let no_dot = "nvim" | to-stow-name
test-result "to-stow-name preserves non-dots" ($no_dot == "nvim") $"Got: ($no_dot)"

# ==============================================================================
# Summary
# ==============================================================================

log+ ""
log+ "=== Test Summary ==="
log+ $"Test directory: ($test_base)"
log+ "You can inspect the test environment before cleanup:"
log+ $"  stow dir: ($stow_dir)"
log+ $"  target dir: ($target_dir)"
log+ $"  target2 dir: ($target2_dir)"
log+ $"  backup dir: ($backup_dir)"
log+ ""
log+ "To clean up, run: rm -rf ($test_base)"

# Keep test directory for inspection
print $"\nTest environment created at: ($test_base)"
print "Inspect it with: ls -laR ($test_base)"
print "Clean up with: rm -rf ($test_base)"
