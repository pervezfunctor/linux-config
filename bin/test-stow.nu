#!/usr/bin/env nu

# Test script for stow functions

use std/log

def log+ [msg: string] { log info $msg }
def warn+ [msg: string] { log warning $msg }
def error+ [msg: string] { log error $msg }

let timestamp = (date now | format date "%Y%m%d_%H%M%S")
let test_base = $env.TMPDIR? | default "/tmp" | path join $"stow-test-($timestamp)"
mkdir $test_base
let source_dir = $test_base | path join "source"
let target_dir = $test_base | path join "target"
let backup_dir = $test_base | path join "backups"

log+ $"Test directory: ($test_base)"

mkdir $source_dir
mkdir $target_dir
mkdir $backup_dir

"vimrc content" | save $"($target_dir)/.vimrc"

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

def stow-add [
    pkg: string,
    path: string,
    target: string,
    src_dir: string
] {
    if not ($path | path exists) {
        error+ $"Path does not exist: ($path)"
        return
    }

    if ($path | path type) != 'file' {
        error make {
            msg: "Not a file"
            label: { text: $path, span: (metadata $path).span }
        }
        return
    }

    let expanded_path = ($path | path expand)
    let expanded_target = ($target | path expand)

    let relative_path = do -i {
        $expanded_path
        | path relative-to $expanded_target
    } | default ($expanded_path | path basename)

    let stow_name = ($relative_path | path split | each { |p| to-stow-name $p })
    let stow_file = $src_dir | path join $pkg | path join ...$stow_name

    ensure-parent-dir $stow_file

    let content = open --raw $path
    $content | save $stow_file

    let target_link = $expanded_target | path join $relative_path
    ensure-parent-dir $target_link
    ^ln -sf $stow_file $target_link

    log+ $"Added: ($path) -> ($pkg)"
}

def stow-apply [
    pkg: string,
    target: string,
    src_dir: string,
    bkp_dir: string
] {
    let stow_pkg_dir = $src_dir | path join $pkg

    if not ($stow_pkg_dir | path exists) {
        error+ $"Package does not exist: ($pkg)"
        return
    }

    let abs_stow_pkg = ($stow_pkg_dir | path expand)
    let abs_target = ($target | path expand)

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
            if not ($bkp_dir | path exists) {
                mkdir $bkp_dir
            }

            let timestamp = (date now | format date '%Y%m%d_%H%M%S')
            let expanded_path = ($file | path expand)
            let relative_path = do -i {
                $expanded_path
                | path relative-to $abs_target
            } | default ($file | path basename)

            let backup_path = $bkp_dir | path join $"($relative_path)-($timestamp)"
            ensure-parent-dir $backup_path

            ^cp $file $backup_path
            ^rm -f $file
        }
    }

    for item in $files_to_link {
        ensure-parent-dir $item.target
        ^ln -sf $item.stow $item.target
    }

    log+ $"Applied: ($pkg)"
}

def test-result [test_name: string, passed: bool, detail: string] {
    let status = if $passed { "[PASS]" } else { "[FAIL]" }
    print $"($status) ($test_name)"
    if not $passed {
        print $"  Detail: ($detail)"
    }
}

log+ "=== Test 1: stow-add creates correct structure ==="
stow-add "vim" $"($target_dir)/.vimrc" $target_dir $source_dir

let stow_file = $source_dir | path join "vim/dot-vimrc"
test-result "creates file in source" ($stow_file | path exists) $"Expected: ($stow_file)"

let symlink = $target_dir | path join ".vimrc"
let is_symlink = ($symlink | path type) == "symlink"
test-result "creates symlink in target" $is_symlink "Should be symlink"

let content = open $symlink
test-result "preserves content" ($content == "vimrc content") $"Got: ($content)"

log+ ""
log+ "=== Test 2: stow-add rejects directories ==="
mkdir $"($target_dir)/.config"
let dir_rejected = (try {
    stow-add "nvim" $"($target_dir)/.config" $target_dir $source_dir
    false
} catch {
    true
})
test-result "rejects directories" $dir_rejected "Should reject directory"

log+ ""
log+ "=== Test 3: stow-apply with backup ==="
let target2_dir = $test_base | path join "target2"
mkdir $target2_dir
"OLD CONTENT" | save $"($target2_dir)/.vimrc"

stow-apply "vim" $target2_dir $source_dir $backup_dir

let backup_files = glob $"($backup_dir)/**/*" | where {|it| ($it | path type) == "file"}
let has_backup = not ($backup_files | is-empty)
test-result "creates backup" $has_backup "Should have backup"

let symlink2 = $target2_dir | path join ".vimrc"
let is_symlink2 = ($symlink2 | path type) == "symlink"
test-result "creates symlink" $is_symlink2 "Should be symlink"

let backup_content = if ($backup_files | is-not-empty) { open ($backup_files | first) } else { "" }
test-result "backup has old content" ($backup_content == "OLD CONTENT") $"Got: ($backup_content)"

log+ ""
log+ "=== Test 4: name conversion ==="
let to_result = to-stow-name ".config"
test-result "to-stow-name" ($to_result == "dot-config") $"Got: ($to_result)"

let from_result = from-stow-name "dot-config"
test-result "from-stow-name" ($from_result == ".config") $"Got: ($from_result)"

log+ ""
log+ $"Test directory: ($test_base)"
print $"Clean up: rm -rf ($test_base)"
