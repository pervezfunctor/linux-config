#!/usr/bin/env nu

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



def test-result [test_name: string, passed: bool, detail: string] {
    let status = if $passed { "[PASS]" } else { "[FAIL]" }
    print $"($status) ($test_name)"
    if not $passed {
        print $"  Detail: ($detail)"
    }
}

let stow_script = ($env.FILE_PWD | path join "stow.nu")

log+ "=== Test 1: stow-add creates correct structure ==="
nu $stow_script add "vim" $"($target_dir)/.vimrc" --target $target_dir --source-dir $source_dir

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
nu $stow_script add "nvim" $"($target_dir)/.config" --target $target_dir --source-dir $source_dir
let dir_rejected = not ($source_dir | path join "nvim" | path exists)
test-result "rejects directories" $dir_rejected "Should reject directory"

log+ ""
log+ "=== Test 3: stow-apply with backup ==="
let target2_dir = $test_base | path join "target2"
mkdir $target2_dir
"OLD CONTENT" | save $"($target2_dir)/.vimrc"

nu $stow_script apply "vim" --target $target2_dir --source-dir $source_dir --backup-dir $backup_dir

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
let to_result = (nu -c $"source ($stow_script); to-stow-name '.config'")
test-result "to-stow-name" ($to_result == "dot-config") $"Got: ($to_result)"

let from_result = (nu -c $"source ($stow_script); from-stow-name 'dot-config'")
test-result "from-stow-name" ($from_result == ".config") $"Got: ($from_result)"

log+ ""
log+ $"Test directory: ($test_base)"
print $"Clean up: rm -rf ($test_base)"
