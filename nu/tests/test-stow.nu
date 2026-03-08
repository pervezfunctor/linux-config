#!/usr/bin/env nu

use std/log

def log+ [msg: string] { log info $msg }
def path-type [path: string] { do -i { $path | path type } | default "none" }
def readlink-path [path: string] { do -i { ^readlink $path } | default "" }
def is-executable [path: string] {
    let result = (^bash -lc 'test -x "$1"' _ $path | complete)
    $result.exit_code == 0
}
def to-stow-segment [name: string] { if ($name | str starts-with ".") { $"dot-($name | str substring 1..)" } else { $name } }
def backup-scope [backup_dir: string, package: string, target: string] {
    let parts = ($target | path expand | path split | each { |segment| if $segment in ['', '/'] { '_root_' } else { to-stow-segment $segment } })
    $backup_dir | path join $package | path join ...$parts
}
def find-files [root: string] {
    let found = (^find $root -type f | complete)
    if $found.exit_code == 0 { $found.stdout | lines | where { |line| not ($line | is-empty) } } else { [] }
}
def check [checks, name: string, passed: bool, detail: string] {
    print $"(if $passed { '[PASS]' } else { '[FAIL]' }) ($name)"
    if not $passed { print $"  Detail: ($detail)" }
    $checks | append { name: $name, passed: $passed, detail: $detail }
}

let now = (date now | format date "%Y%m%d_%H%M%S")
let test_base = ($env.TMPDIR? | default "/tmp" | path join $"stow-test-($now)")
let source_dir = ($test_base | path join "source")
let target_dir = ($test_base | path join "target")
let backup_dir = ($test_base | path join "backups")
let stow_script = ($env.FILE_PWD | path join ".." "stow.nu" | path expand)

mkdir $test_base
mkdir $source_dir
mkdir $target_dir
mkdir $backup_dir
mkdir ($test_base | path join ".linux-config-logs")
load-env { HOME: $test_base }

def --wrapped run-stow [...args: string] { ^nu $stow_script ...$args | complete }
def run-inline [expr: string] { ^nu -c $expr | complete }

mut checks = []
log+ $"Test directory: ($test_base)"

"vimrc content" | save ($target_dir | path join ".vimrc")
let add_basic = (run-stow add "vim" ($target_dir | path join ".vimrc") --target $target_dir --source-dir $source_dir)
let stow_vim = ($source_dir | path join "vim/dot-vimrc")
let target_vim = ($target_dir | path join ".vimrc")
$checks = (check $checks "add basic exits cleanly" ($add_basic.exit_code == 0) $add_basic.stderr)
$checks = (check $checks "add basic stages file" ($stow_vim | path exists) $stow_vim)
$checks = (check $checks "add basic symlinks target" ((path-type $target_vim) == "symlink") (path-type $target_vim))
$checks = (check $checks "add basic preserves content" ((open $target_vim) == "vimrc content") "content mismatch")

mkdir ($target_dir | path join ".local/bin")
let exec_target = ($target_dir | path join ".local/bin/demo")
"#!/usr/bin/env bash\necho demo" | save $exec_target
^chmod 755 $exec_target
let add_exec = (run-stow add "bin" $exec_target --target $target_dir --source-dir $source_dir)
let staged_exec = ($source_dir | path join "bin/dot-local/bin/demo")
$checks = (check $checks "add executable exits cleanly" ($add_exec.exit_code == 0) $add_exec.stderr)
$checks = (check $checks "add preserves staged executable bit" (is-executable $staged_exec) $staged_exec)
$checks = (check $checks "add preserves deployed executable bit" (is-executable $exec_target) $exec_target)

mkdir ($target_dir | path join ".config")
let add_dir = (run-stow add "nvim" ($target_dir | path join ".config") --target $target_dir --source-dir $source_dir)
$checks = (check $checks "add rejects directories" ($add_dir.exit_code != 0) $add_dir.stderr)

let nested_dir = ($target_dir | path join ".config/nvim")
mkdir $nested_dir
"lua config" | save ($nested_dir | path join "init.lua")
let add_nested = (run-stow add "nvim" ($nested_dir | path join "init.lua") --target $target_dir --source-dir $source_dir)
let staged_nested = ($source_dir | path join "nvim/dot-config/nvim/init.lua")
$checks = (check $checks "add nested exits cleanly" ($add_nested.exit_code == 0) $add_nested.stderr)
$checks = (check $checks "add nested stages dot-path" ($staged_nested | path exists) $staged_nested)

^rm -f $target_vim
"vimrc content v2" | save $target_vim
let add_refresh = (run-stow add "vim" $target_vim --target $target_dir --source-dir $source_dir)
$checks = (check $checks "re-add exits cleanly" ($add_refresh.exit_code == 0) $add_refresh.stderr)
$checks = (check $checks "re-add refreshes staged content" ((open $stow_vim) == "vimrc content v2") "staged file stale")

let aliases_real = ($test_base | path join "aliases")
"alias ll='ls -la'" | save $aliases_real
let aliases_target = ($target_dir | path join ".aliases")
^ln -sf $aliases_real $aliases_target
let add_symlink = (run-stow add "shell" $aliases_target --target $target_dir --source-dir $source_dir)
let staged_alias = ($source_dir | path join "shell/dot-aliases")
$checks = (check $checks "add rejects symlink to file" ($add_symlink.exit_code != 0) $add_symlink.stderr)
$checks = (check $checks "add symlink rejection does not stage file" (not ($staged_alias | path exists)) $staged_alias)

let dir_link = ($target_dir | path join ".config-link")
^ln -sf ($target_dir | path join ".config") $dir_link
let add_dir_link = (run-stow add "bad" $dir_link --target $target_dir --source-dir $source_dir)
$checks = (check $checks "add rejects symlink to directory" ($add_dir_link.exit_code != 0) $add_dir_link.stderr)

let rel_root = ($test_base | path join "rel-source")
mkdir $rel_root
mkdir ($rel_root | path join "source")
mkdir ($rel_root | path join "target")
"rel config" | save ($rel_root | path join "target/.relrc")
let rel_expr = $"cd '($rel_root)'; nu '($stow_script)' add relpkg target/.relrc --target target --source-dir source"
let rel_add = (run-inline $rel_expr)
let rel_stow = ($rel_root | path join "source/relpkg/dot-relrc")
let rel_target = ($rel_root | path join "target/.relrc")
$checks = (check $checks "relative source add exits cleanly" ($rel_add.exit_code == 0) $rel_add.stderr)
$checks = (check $checks "relative source creates staged file" ($rel_stow | path exists) $rel_stow)
$checks = (check $checks "relative source target is symlink" ((path-type $rel_target) == "symlink") (path-type $rel_target))

let outside = ($test_base | path join "outside.txt")
"outside content" | save $outside
let add_outside = (run-stow add "out" $outside --target $target_dir --source-dir $source_dir)
$checks = (check $checks "add outside target fails non-zero" ($add_outside.exit_code != 0) $add_outside.stderr)

let target2 = ($test_base | path join "target2")
mkdir $target2
"OLD VIMRC CONTENT" | save ($target2 | path join ".vimrc")
let apply_basic = (run-stow apply "vim" --target $target2 --source-dir $source_dir --backup-dir $backup_dir)
let vim_backups = (find-files (backup-scope $backup_dir "vim" $target2) | where { |p| (($p | path basename) | str starts-with ".vimrc-") })
let vim_backup_content = if ($vim_backups | is-empty) { "" } else { open ($vim_backups | first) }
$checks = (check $checks "apply exits cleanly" ($apply_basic.exit_code == 0) $apply_basic.stderr)
$checks = (check $checks "apply creates package backup" (not ($vim_backups | is-empty)) "no backup found")
$checks = (check $checks "apply symlinks target" ((path-type ($target2 | path join ".vimrc")) == "symlink") (path-type ($target2 | path join ".vimrc")))
$checks = (check $checks "apply backup content matches" ($vim_backup_content == "OLD VIMRC CONTENT") "backup mismatch")

let target3 = ($test_base | path join "target3")
mkdir $target3
^ln -sf "/dummy" ($target3 | path join ".vimrc")
let apply_replace = (run-stow apply "vim" --target $target3 --source-dir $source_dir --backup-dir $backup_dir)
$checks = (check $checks "apply over existing symlink exits cleanly" ($apply_replace.exit_code == 0) $apply_replace.stderr)
$checks = (check $checks "apply replaces existing symlink" ((readlink-path ($target3 | path join ".vimrc")) | str contains "/source/vim/") (readlink-path ($target3 | path join ".vimrc")))

let target4 = ($test_base | path join "target4")
mkdir $target4
mkdir ($target4 | path join ".vimrc")
let apply_dir = (run-stow apply "vim" --target $target4 --source-dir $source_dir --backup-dir $backup_dir)
$checks = (check $checks "apply fails on directory collision" ($apply_dir.exit_code != 0) $apply_dir.stderr)

let apply_missing = (run-stow apply "imaginary" --target $target2 --source-dir $source_dir --backup-dir $backup_dir)
$checks = (check $checks "apply missing package fails non-zero" ($apply_missing.exit_code != 0) $apply_missing.stderr)

let restore_basic = (run-stow restore "vim" --target $target2 --source-dir $source_dir --backup-dir $backup_dir)
$checks = (check $checks "restore exits cleanly" ($restore_basic.exit_code == 0) $restore_basic.stderr)
$checks = (check $checks "restore recreates real file" ((path-type ($target2 | path join ".vimrc")) == "file") (path-type ($target2 | path join ".vimrc")))
$checks = (check $checks "restore recovers original content" ((open ($target2 | path join ".vimrc")) == "OLD VIMRC CONTENT") "restore mismatch")

let target_remove = ($test_base | path join "target-remove")
mkdir $target_remove
"REMOVE ORIGINAL" | save ($target_remove | path join ".vimrc")
let apply_remove = (run-stow apply "vim" --target $target_remove --source-dir $source_dir --backup-dir $backup_dir)
let remove_basic = (run-stow remove "vim" --target $target_remove --source-dir $source_dir --backup-dir $backup_dir)
$checks = (check $checks "apply for remove-with-backup exits cleanly" ($apply_remove.exit_code == 0) $apply_remove.stderr)
$checks = (check $checks "remove restores backup content" (($remove_basic.exit_code == 0) and ((open ($target_remove | path join ".vimrc")) == "REMOVE ORIGINAL")) $remove_basic.stderr)
$checks = (check $checks "remove restores real file" ((path-type ($target_remove | path join ".vimrc")) == "file") (path-type ($target_remove | path join ".vimrc")))

let target_remove_clean = ($test_base | path join "target-remove-clean")
mkdir $target_remove_clean
let apply_remove_clean = (run-stow apply "vim" --target $target_remove_clean --source-dir $source_dir --backup-dir $backup_dir)
let remove_clean = (run-stow remove "vim" --target $target_remove_clean --source-dir $source_dir --backup-dir $backup_dir)
$checks = (check $checks "apply for remove-without-backup exits cleanly" ($apply_remove_clean.exit_code == 0) $apply_remove_clean.stderr)
$checks = (check $checks "remove without backup exits cleanly" ($remove_clean.exit_code == 0) $remove_clean.stderr)
$checks = (check $checks "remove without backup deletes managed symlink" (not (($target_remove_clean | path join ".vimrc") | path exists)) ($target_remove_clean | path join ".vimrc"))

let target_remove_drift = ($test_base | path join "target-remove-drift")
mkdir $target_remove_drift
let apply_remove_drift = (run-stow apply "vim" --target $target_remove_drift --source-dir $source_dir --backup-dir $backup_dir)
^rm -f ($target_remove_drift | path join ".vimrc")
^ln -sf "/dummy" ($target_remove_drift | path join ".vimrc")
let remove_drift = (run-stow remove "vim" --target $target_remove_drift --source-dir $source_dir --backup-dir $backup_dir)
$checks = (check $checks "apply for remove-drift test exits cleanly" ($apply_remove_drift.exit_code == 0) $apply_remove_drift.stderr)
$checks = (check $checks "remove fails for unmanaged symlink drift" ($remove_drift.exit_code != 0) $remove_drift.stderr)

let target_status_ok = ($test_base | path join "target-status-ok")
mkdir $target_status_ok
let apply_status_ok = (run-stow apply "vim" --target $target_status_ok --source-dir $source_dir --backup-dir $backup_dir)
let status_ok = (run-stow status "vim" --target $target_status_ok --source-dir $source_dir --backup-dir $backup_dir)
let status_ok_out = ($status_ok.stdout + $status_ok.stderr)
let doctor_ok = (run-stow doctor "vim" --target $target_status_ok --source-dir $source_dir --backup-dir $backup_dir)
$checks = (check $checks "apply for status-ok test exits cleanly" ($apply_status_ok.exit_code == 0) $apply_status_ok.stderr)
$checks = (check $checks "status reports managed target" (($status_ok.exit_code == 0) and ($status_ok_out | str contains "managed")) $status_ok_out)
$checks = (check $checks "doctor exits cleanly for managed target" ($doctor_ok.exit_code == 0) ($doctor_ok.stdout + $doctor_ok.stderr))

let target_status_missing = ($test_base | path join "target-status-missing")
mkdir $target_status_missing
let status_missing = (run-stow status "vim" --target $target_status_missing --source-dir $source_dir --backup-dir $backup_dir)
let status_missing_out = ($status_missing.stdout + $status_missing.stderr)
let doctor_missing = (run-stow doctor "vim" --target $target_status_missing --source-dir $source_dir --backup-dir $backup_dir)
let doctor_missing_out = ($doctor_missing.stdout + $doctor_missing.stderr)
$checks = (check $checks "status reports missing target" (($status_missing.exit_code == 0) and ($status_missing_out | str contains "missing")) $status_missing_out)
$checks = (check $checks "doctor fails for missing target" (($doctor_missing.exit_code != 0) and ($doctor_missing_out | str contains "missing")) $doctor_missing_out)

let target_status_drift = ($test_base | path join "target-status-drift")
mkdir $target_status_drift
let apply_status_drift = (run-stow apply "vim" --target $target_status_drift --source-dir $source_dir --backup-dir $backup_dir)
^rm -f ($target_status_drift | path join ".vimrc")
^ln -sf "/dummy" ($target_status_drift | path join ".vimrc")
let status_drift = (run-stow status "vim" --target $target_status_drift --source-dir $source_dir --backup-dir $backup_dir)
let status_drift_out = ($status_drift.stdout + $status_drift.stderr)
let doctor_drift = (run-stow doctor "vim" --target $target_status_drift --source-dir $source_dir --backup-dir $backup_dir)
let doctor_drift_out = ($doctor_drift.stdout + $doctor_drift.stderr)
$checks = (check $checks "apply for status-drift test exits cleanly" ($apply_status_drift.exit_code == 0) $apply_status_drift.stderr)
$checks = (check $checks "status reports foreign symlink drift" (($status_drift.exit_code == 0) and ($status_drift_out | str contains "foreign-symlink")) $status_drift_out)
$checks = (check $checks "doctor fails for foreign symlink drift" (($doctor_drift.exit_code != 0) and ($doctor_drift_out | str contains "foreign-symlink")) $doctor_drift_out)

let collision_root = ($test_base | path join "collision-root")
mkdir $collision_root
let collision_base = ($collision_root | path join ".vimrc-20260101_010101")
let collision_one = ($collision_root | path join ".vimrc-20260101_010101-1")
"first" | save $collision_base
"second" | save $collision_one
let next_collision = (run-inline $"source ($stow_script); unique-backup-path '($collision_root)' '.vimrc' '20260101_010101'")
let next_collision_out = ($next_collision.stdout | str trim)
$checks = (check $checks "unique-backup-path adds collision suffix" (($next_collision.exit_code == 0) and ($next_collision_out == ($collision_root | path join ".vimrc-20260101_010101-2"))) ($next_collision.stdout + $next_collision.stderr))

let target5 = ($test_base | path join "target5")
mkdir $target5
"content 1" | save ($target5 | path join ".vimrc")
let apply_latest = (run-stow apply "vim" --target $target5 --source-dir $source_dir --backup-dir $backup_dir)
let target5_backup_root = (backup-scope $backup_dir "vim" $target5)
let target5_old = ($target5_backup_root | path join ".vimrc-20000101_000000")
let target5_new = ($target5_backup_root | path join ".vimrc-20291231_235959")
mkdir ($target5_old | path dirname)
"very old content" | save --force $target5_old
"very future content" | save --force $target5_new
let restore_latest = (run-stow restore "vim" --target $target5 --source-dir $source_dir --backup-dir $backup_dir)
$checks = (check $checks "apply for latest-backup test exits cleanly" ($apply_latest.exit_code == 0) $apply_latest.stderr)
$checks = (check $checks "restore chooses newest timestamp" (($restore_latest.exit_code == 0) and ((open ($target5 | path join ".vimrc")) == "very future content")) $restore_latest.stderr)

let target5_collision = ($test_base | path join "target5-collision")
mkdir $target5_collision
let target5_collision_backup_root = (backup-scope $backup_dir "vim" $target5_collision)
let target5_collision_base = ($target5_collision_backup_root | path join ".vimrc-20260101_010101")
let target5_collision_one = ($target5_collision_backup_root | path join ".vimrc-20260101_010101-1")
let target5_collision_two = ($target5_collision_backup_root | path join ".vimrc-20260101_010101-2")
mkdir ($target5_collision_base | path dirname)
"collision base" | save --force $target5_collision_base
"collision one" | save --force $target5_collision_one
"collision two" | save --force $target5_collision_two
let restore_collision = (run-stow restore "vim" --target $target5_collision --source-dir $source_dir --backup-dir $backup_dir)
$checks = (check $checks "restore chooses newest collision suffix" (($restore_collision.exit_code == 0) and ((open ($target5_collision | path join ".vimrc")) == "collision two")) $restore_collision.stderr)

mkdir ($source_dir | path join "altvim")
"ALT STAGED CONTENT" | save ($source_dir | path join "altvim/dot-vimrc")
let target6 = ($test_base | path join "target6")
mkdir $target6
"ORIGINAL VIM" | save ($target6 | path join ".vimrc")
let apply_vim_ns = (run-stow apply "vim" --target $target6 --source-dir $source_dir --backup-dir $backup_dir)
^rm -f ($target6 | path join ".vimrc")
"ORIGINAL ALTVIM" | save ($target6 | path join ".vimrc")
let apply_alt_ns = (run-stow apply "altvim" --target $target6 --source-dir $source_dir --backup-dir $backup_dir)
let restore_vim_ns = (run-stow restore "vim" --target $target6 --source-dir $source_dir --backup-dir $backup_dir)
$checks = (check $checks "apply namespaced vim backup exits cleanly" ($apply_vim_ns.exit_code == 0) $apply_vim_ns.stderr)
$checks = (check $checks "apply namespaced alt backup exits cleanly" ($apply_alt_ns.exit_code == 0) $apply_alt_ns.stderr)
$checks = (check $checks "restore vim package succeeds" (($restore_vim_ns.exit_code == 0) and ((open ($target6 | path join ".vimrc")) == "ORIGINAL VIM")) $restore_vim_ns.stderr)
let restore_alt_ns = (run-stow restore "altvim" --target $target6 --source-dir $source_dir --backup-dir $backup_dir)
$checks = (check $checks "restore alt package succeeds" (($restore_alt_ns.exit_code == 0) and ((open ($target6 | path join ".vimrc")) == "ORIGINAL ALTVIM")) $restore_alt_ns.stderr)

mkdir ($target2 | path join ".config/nvim")
"fake file" | save --force ($target2 | path join ".config/nvim/init.lua")
let restore_missing_file = (run-stow restore "nvim" --target $target2 --source-dir $source_dir --backup-dir $backup_dir)
$checks = (check $checks "restore fails for file without backup" ($restore_missing_file.exit_code != 0) $restore_missing_file.stderr)

^rm -f ($target2 | path join ".config/nvim/init.lua")
^ln -sf "/dummy" ($target2 | path join ".config/nvim/init.lua")
let restore_missing_link = (run-stow restore "nvim" --target $target2 --source-dir $source_dir --backup-dir $backup_dir)
let restore_missing_link_out = ($restore_missing_link.stdout + $restore_missing_link.stderr)
$checks = (check $checks "restore warns for symlink without backup" (($restore_missing_link.exit_code == 0) and ($restore_missing_link_out | str contains "Warning: No backup found for")) $restore_missing_link_out)

let target7 = ($test_base | path join "target7")
mkdir $target7
"RESTORE ME" | save ($target7 | path join ".vimrc")
let apply_restore_dir = (run-stow apply "vim" --target $target7 --source-dir $source_dir --backup-dir $backup_dir)
^rm -f ($target7 | path join ".vimrc")
mkdir ($target7 | path join ".vimrc")
let restore_dir = (run-stow restore "vim" --target $target7 --source-dir $source_dir --backup-dir $backup_dir)
$checks = (check $checks "apply for restore-dir test exits cleanly" ($apply_restore_dir.exit_code == 0) $apply_restore_dir.stderr)
$checks = (check $checks "restore fails on directory collision" ($restore_dir.exit_code != 0) $restore_dir.stderr)

let to_name = (run-inline $"source ($stow_script); to-stow-name '.config'")
let from_name = (run-inline $"source ($stow_script); from-stow-name 'dot-config'")
$checks = (check $checks "to-stow-name works" (($to_name.exit_code == 0) and (($to_name.stdout | str trim) == "dot-config")) $to_name.stdout)
$checks = (check $checks "from-stow-name works" (($from_name.exit_code == 0) and (($from_name.stdout | str trim) == ".config")) $from_name.stdout)

let failed = ($checks | where { |item| not $item.passed })
print ""
print $"Summary: (($checks | length) - ($failed | length)) passed, ($failed | length) failed"
do -i { ^rm -rf $test_base }
if (not ($failed | is-empty)) { exit 1 }
