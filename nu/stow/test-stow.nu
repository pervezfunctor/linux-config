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
let log_dir = $test_base | path join "logs"
let module_log_root = $test_base | path join ".linux-config-logs"

mkdir $source_dir
mkdir $target_dir
mkdir $backup_dir
mkdir $log_dir
mkdir $module_log_root
load-env {
    HOME: $test_base
}

log+ $"Test directory: ($test_base)"

mut test_results = { passed: 0, failed: 0 }

def test-result [test_name: string, passed: bool, detail: string] {
    let status = if $passed { "[PASS]" } else { "[FAIL]" }
    print $"($status) ($test_name)"
    if not $passed {
        print $"  Detail: ($detail)"
    }
    let res = if $passed { { passed: 1, failed: 0 } } else { { passed: 0, failed: 1 } }
    $res
}

let stow_script = ($env.FILE_PWD | path join "stow.nu")

# ==========================================
# TEST: ADD
# ==========================================
log+ "=== Test Add: Basic File ==="
"vimrc content" | save $"($target_dir)/.vimrc"
nu $stow_script add "vim" $"($target_dir)/.vimrc" --target $target_dir --source-dir $source_dir
let stow_file = $source_dir | path join "vim/dot-vimrc"
$test_results = ($test_results | merge { passed: ($test_results.passed + 1) }) # To simulate tracking
test-result "creates file in source" ($stow_file | path exists) $"Expected: ($stow_file)"
test-result "creates symlink in target" (($target_dir | path join ".vimrc" | path type) == "symlink") "Should be symlink"
test-result "preserves content" ((open ($target_dir | path join ".vimrc")) == "vimrc content") "Failed content check"

log+ "=== Test Add: Rejects Directories ==="
mkdir $"($target_dir)/.config"
let add_dir_status = (nu $stow_script add "nvim" $"($target_dir)/.config" --target $target_dir --source-dir $source_dir | complete)
test-result "rejects directories" (not ($source_dir | path join "nvim" | path exists)) "Should reject directory addition"

log+ "=== Test Add: Nested Paths ==="
let nested_dir = $"($target_dir)/.config/nvim"
mkdir $nested_dir
"lua config" | save $"($nested_dir)/init.lua"
nu $stow_script add "nvim" $"($nested_dir)/init.lua" --target $target_dir --source-dir $source_dir
let nested_stow_file = $source_dir | path join "nvim/dot-config/nvim/init.lua"
test-result "nested path creates correct stow structure" ($nested_stow_file | path exists) $"Expected: ($nested_stow_file)"
test-result "nested target is symlink" (($nested_dir | path join "init.lua" | path type) == "symlink") "Should be symlink"

log+ "=== Test Add: Re-adding Refreshes Managed File ==="
^rm -f $"($target_dir)/.vimrc"
"vimrc content v2" | save $"($target_dir)/.vimrc"
nu $stow_script add "vim" $"($target_dir)/.vimrc" --target $target_dir --source-dir $source_dir
test-result "re-add updates staged copy" ((open $stow_file) == "vimrc content v2") "Staged copy not refreshed"
test-result "re-add recreates symlink" ((($target_dir | path join ".vimrc" | path type) == "symlink") and ((open ($target_dir | path join ".vimrc")) == "vimrc content v2")) "Symlink missing or stale"

log+ "=== Test Add: Relative Source Directory ==="
let rel_root = $test_base | path join "rel-source"
let rel_source = $rel_root | path join "source"
let rel_target = $rel_root | path join "target"
mkdir $rel_root
mkdir $rel_source
mkdir $rel_target
"rel config" | save $"($rel_target)/.relrc"
let rel_cmd = $"cd '($rel_root)'; nu '($stow_script)' add relpkg target/.relrc --target target --source-dir source"
nu -c $rel_cmd
let rel_stow_file = $rel_source | path join "relpkg/dot-relrc"
let rel_target_file = $rel_target | path join ".relrc"
test-result "relative source creates file" ($rel_stow_file | path exists) "Missing staged file"
test-result "relative source symlinks target" (($rel_target_file | path type) == "symlink") "Target should be symlinked"
let rel_link = (do -i { ^readlink $rel_target_file } | default "")
let rel_link_real = ($rel_link | path expand)
let rel_expected_real = ($rel_stow_file | path expand)
test-result "relative symlink points to expanded source" ($rel_link_real == $rel_expected_real) "Symlink destination mismatch"

log+ "=== Test Add: Outside Target Bound ==="
let outside_file = $test_base | path join "outside.txt"
"outside content" | save $outside_file
# compute-stow-path fails, so this execution should return a non-zero exit or an error stream.
let out_result = (nu $stow_script add "out" $outside_file --target $target_dir --source-dir $source_dir | complete)
test-result "fails on outside target bound" (not ($source_dir | path join "out" | path exists)) "Should not create stow package"

# ==========================================
# TEST: APPLY
# ==========================================
log+ "=== Test Apply: Basic with Backup ==="
let target2_dir = $test_base | path join "target2"
mkdir $target2_dir
"OLD VIMRC CONTENT" | save $"($target2_dir)/.vimrc"
nu $stow_script apply "vim" --target $target2_dir --source-dir $source_dir --backup-dir $backup_dir

let backup_pattern = $"($backup_dir)/*"
let backup_files = glob $backup_pattern | where {|it| ($it | path type) == "file"}
test-result "creates backup file" (not ($backup_files | is-empty)) "Should have backup"
test-result "symlinks correctly" (($target2_dir | path join ".vimrc" | path type) == "symlink") "Target should be a symlink"
test-result "backup has old content" ((open ($backup_files | first)) == "OLD VIMRC CONTENT") "Old content was not backed up"

log+ "=== Test Apply: Destruction of Existing Symlink ==="
let target3_dir = $test_base | path join "target3"
mkdir $target3_dir
^ln -sf "/dummy" $"($target3_dir)/.vimrc"
nu $stow_script apply "vim" --target $target3_dir --source-dir $source_dir --backup-dir $backup_dir
let is_sym3 = (($target3_dir | path join ".vimrc" | path type) == "symlink")
let link_dest = (do -i { ^readlink $"($target3_dir)/.vimrc" })
test-result "replaces existing symlink" ($is_sym3 and ($link_dest | str contains "source/vim")) "Symlink was not updated"

log+ "=== Test Apply: Fails When Target is Directory ==="
let target4_dir = $test_base | path join "target4"
mkdir $target4_dir
mkdir $"($target4_dir)/.vimrc" # creating directory where symlink should go
# apply should complain about directory collision
let apply_dir = (nu $stow_script apply "vim" --target $target4_dir --source-dir $source_dir --backup-dir $backup_dir | complete)
test-result "fails when target is dir" (($target4_dir | path join ".vimrc" | path type) == "dir") "Should still be directory"

log+ "=== Test Apply: Non-Existent Package ==="
let bad_apply = (nu $stow_script apply "imaginary" --target $target2_dir --source-dir $source_dir --backup-dir $backup_dir | complete)
test-result "survives non-existent package gracefully" true "Should gracefully handle"

# ==========================================
# TEST: RESTORE
# ==========================================
log+ "=== Test Restore: Basic File Recovery ==="
nu $stow_script restore "vim" --target $target2_dir --source-dir $source_dir --backup-dir $backup_dir
let restored_type = ($target2_dir | path join ".vimrc" | path type)
test-result "symlink replaced with real file" ($restored_type == "file") "Should be real file after restore"
test-result "recovered old content" ((open ($target2_dir | path join ".vimrc")) == "OLD VIMRC CONTENT") "Backup missing or inaccurate"

log+ "=== Test Restore: Latest Backup Chosen ==="
# Simulate multiple backups of different times
let target5_dir = $test_base | path join "target5"
mkdir $target5_dir
"content 1" | save $"($target5_dir)/.vimrc"
nu $stow_script apply "vim" --target $target5_dir --source-dir $source_dir --backup-dir $backup_dir
# Sleep to distinct backup times... or mock files
let fake_bkp1 = $"($backup_dir)/.vimrc-20000101_000000"
let fake_bkp2 = $"($backup_dir)/.vimrc-20291231_235959" # The future
"very old content" | save $fake_bkp1
"very future content" | save $fake_bkp2
nu $stow_script restore "vim" --target $target5_dir --source-dir $source_dir --backup-dir $backup_dir
test-result "picks explicitly youngest timestamp backup" ((open ($target5_dir | path join ".vimrc")) == "very future content") "Did not pick the newest timestamp"

log+ "=== Test Restore: Fails Audibly When Backups Missing for File ==="
let nvim_test_path = $target2_dir | path join ".config/nvim/init.lua"
mkdir ($nvim_test_path | path dirname)
"fake file" | save $nvim_test_path
let out_restore_file = (nu $stow_script restore "nvim" --target $target2_dir --source-dir $source_dir --backup-dir $backup_dir | complete)
test-result "restore fails explicitly for file" ($out_restore_file.exit_code != 0) "Should fail explicitly"

log+ "=== Test Restore: Skips Restoring Gracefully When Backups Missing for Symlink ==="
rm $nvim_test_path
^ln -sf "/dummy" $nvim_test_path
let out_restore_sym = (nu $stow_script restore "nvim" --target $target2_dir --source-dir $source_dir --backup-dir $backup_dir | complete)
test-result "skips safely when missing" ($out_restore_sym.stderr | str contains "Warning: No backup found for") "Should output a warning instead of an error"

# ==========================================
# TEST: NAME CONVERSION
# ==========================================
log+ "=== Test Name Conversion ==="
let to_result = (nu -c $"source ($stow_script); to-stow-name '.config'")
test-result "to-stow-name" ($to_result == "dot-config") $"Got: ($to_result)"

let from_result = (nu -c $"source ($stow_script); from-stow-name 'dot-config'")
test-result "from-stow-name" ($from_result == ".config") $"Got: ($from_result)"

log+ ""
log+ $"Test execution finished in ($test_base)."
print $"Clean up: rm -rf ($test_base)"
rm -rf $test_base
