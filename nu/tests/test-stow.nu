#!/usr/bin/env nu

use std/log

def log+ [msg: string] { log info $msg }
def path-type [path: string] {
    do -i { $path | path type } | default "none"
}
def readlink-path [path: string] {
    do -i { ^readlink $path } | default ""
}
def is-executable [path: string] {
    let result = (^bash -lc 'test -x "$1"' _ $path | complete)
    $result.exit_code == 0
}
def to-stow-segment [name: string] {
    if ($name | str starts-with ".") {
        $"dot-($name | str substring 1..)"
    } else {
        $name
    }
}
def backup-scope [
    backup_dir: string
    package: string
    target: string
] {
    let parts = (
        $target
        | path expand
        | path split
        | each { |segment|
            if $segment in ['', '/'] { '_root_' } else {
                to-stow-segment $segment
            }
        }
    )
    $backup_dir | path join $package | path join ...$parts
}
def find-files [root: string] {
    let found = (^find $root -type f | complete)
    if $found.exit_code == 0 {
        $found.stdout | lines | where { |line| not ($line | is-empty) }
    } else {
        []
    }
}
def check [name: string, passed: bool, detail: string] {
    print $"(if $passed { '[PASS]' } else { '[FAIL]' }) ($name)"
    if not $passed { print $"  Detail: ($detail)" }
    { name: $name, passed: $passed, detail: $detail }
}

def --wrapped run-stow-cmd [stow_script: string, ...args: string] {
    ^nu -n $stow_script ...$args | complete
}
def run-inline [expr: string] { ^nu -n -c $expr | complete }

def test_add_basic [
    test_base: string
    source_dir: string
    target_dir: string
    stow_script: string
] {
    "vimrc content" | save ($target_dir | path join ".vimrc")
    let add_basic = (
        run-stow-cmd $stow_script add "vim" ($target_dir | path join ".vimrc")
            --target $target_dir
            --source-dir $source_dir
    )
    let stow_vim = ($source_dir | path join "vim/dot-vimrc")
    let target_vim = ($target_dir | path join ".vimrc")

    [
        (check
            "add basic exits cleanly"
            ($add_basic.exit_code == 0)
            $add_basic.stderr)
        (check
            "add basic stages file"
            ($stow_vim | path exists)
            $stow_vim)
        (check
            "add basic symlinks target"
            ((path-type $target_vim) == "symlink")
            (path-type $target_vim))
        (check
            "add basic preserves content"
            ((open $target_vim) == "vimrc content")
            "content mismatch")
    ]
}

def test_add_executable [
    test_base: string
    source_dir: string
    target_dir: string
    stow_script: string
] {
    mkdir ($target_dir | path join ".local/bin")
    let exec_target = ($target_dir | path join ".local/bin/demo")
    "#!/usr/bin/env bash\necho demo" | save $exec_target
    ^chmod 755 $exec_target
    let add_exec = (
        run-stow-cmd $stow_script add "bin" $exec_target
            --target $target_dir
            --source-dir $source_dir
    )
    let staged_exec = ($source_dir | path join "bin/dot-local/bin/demo")

    [
        (check
            "add executable exits cleanly"
            ($add_exec.exit_code == 0)
            $add_exec.stderr)
        (check
            "add preserves staged executable bit"
            (is-executable $staged_exec)
            $staged_exec)
        (check
            "add preserves deployed executable bit"
            (is-executable $exec_target)
            $exec_target)
    ]
}

def test_add_nested [
    test_base: string
    source_dir: string
    target_dir: string
    stow_script: string
] {
    mkdir ($target_dir | path join ".config")
    let add_dir = (
        run-stow-cmd $stow_script add "nvim" ($target_dir | path join ".config")
            --target $target_dir
            --source-dir $source_dir
    )

    let nested_dir = ($target_dir | path join ".config/nvim")
    mkdir $nested_dir
    "lua config" | save ($nested_dir | path join "init.lua")
    let nested_init = ($nested_dir | path join "init.lua")
    let add_nested = (
        run-stow-cmd $stow_script add "nvim" $nested_init
            --target $target_dir
            --source-dir $source_dir
    )
    let staged_nested = (
        $source_dir | path join "nvim/dot-config/nvim/init.lua"
    )

    let target_vim = ($target_dir | path join ".vimrc")
    ^rm -f $target_vim
    "vimrc content v2" | save $target_vim
    let add_refresh = (
        run-stow-cmd $stow_script add "vim" $target_vim
            --target $target_dir
            --source-dir $source_dir
    )
    let stow_vim = ($source_dir | path join "vim/dot-vimrc")

    let aliases_real = ($test_base | path join "aliases")
    "alias ll='ls -la'" | save $aliases_real
    let aliases_target = ($target_dir | path join ".aliases")
    ^ln -sf $aliases_real $aliases_target
    let add_symlink = (
        run-stow-cmd $stow_script add "shell" $aliases_target
            --target $target_dir
            --source-dir $source_dir
    )
    let staged_alias = ($source_dir | path join "shell/dot-aliases")

    let dir_link = ($target_dir | path join ".config-link")
    ^ln -sf ($target_dir | path join ".config") $dir_link
    let add_dir_link = (
        run-stow-cmd $stow_script add "bad" $dir_link
            --target $target_dir
            --source-dir $source_dir
    )

    let rel_root = ($test_base | path join "rel-source")
    mkdir $rel_root
    mkdir ($rel_root | path join "source")
    mkdir ($rel_root | path join "target")
    "rel config" | save ($rel_root | path join "target/.relrc")
    let rel_expr = (
        "cd '" + $rel_root + "'; "
        + "nu -n '" + $stow_script + "' add relpkg target/.relrc "
        + "--target target --source-dir source"
    )
    let rel_add = (run-inline $rel_expr)
    let rel_stow = ($rel_root | path join "source/relpkg/dot-relrc")
    let rel_target = ($rel_root | path join "target/.relrc")

    let outside = ($test_base | path join "outside.txt")
    "outside content" | save $outside
    let add_outside = (
        run-stow-cmd $stow_script add "out" $outside
            --target $target_dir
            --source-dir $source_dir
    )

    let broken_missing = ($test_base | path join "missing-real")
    if ($broken_missing | path exists) {
        ^rm -f $broken_missing
    }
    let broken_target = ($target_dir | path join ".brokenrc")
    ^ln -sf $broken_missing $broken_target
    let add_broken = (
        run-stow-cmd $stow_script add "broken" $broken_target
            --target $target_dir
            --source-dir $source_dir
    )
    let staged_broken = ($source_dir | path join "broken/dot-brokenrc")

    [
        (check
            "add rejects directories"
            ($add_dir.exit_code != 0)
            $add_dir.stderr)
        (check
            "add nested exits cleanly"
            ($add_nested.exit_code == 0)
            $add_nested.stderr)
        (check
            "add nested stages dot-path"
            ($staged_nested | path exists)
            $staged_nested)
        (check
            "re-add exits cleanly"
            ($add_refresh.exit_code == 0)
            $add_refresh.stderr)
        (check
            "re-add refreshes staged content"
            ((open $stow_vim) == "vimrc content v2")
            "staged file stale")
        (check
            "add rejects symlink to file"
            ($add_symlink.exit_code != 0)
            $add_symlink.stderr)
        (check
            "add symlink rejection does not stage file"
            (not ($staged_alias | path exists))
            $staged_alias)
        (check
            "add rejects symlink to directory"
            ($add_dir_link.exit_code != 0)
            $add_dir_link.stderr)
        (check
            "relative source add exits cleanly"
            ($rel_add.exit_code == 0)
            $rel_add.stderr)
        (check
            "relative source creates staged file"
            ($rel_stow | path exists)
            $rel_stow)
        (check
            "relative source target is symlink"
            ((path-type $rel_target) == "symlink")
            (path-type $rel_target))
        (check
            "add outside target fails non-zero"
            ($add_outside.exit_code != 0)
            $add_outside.stderr)
        (check
            "add rejects broken symlink"
            ($add_broken.exit_code != 0)
            $add_broken.stderr)
        (check
            "add broken symlink skips staging"
            (not ($staged_broken | path exists))
            $staged_broken)
    ]
}

def test_apply_and_restore [
    test_base: string
    source_dir: string
    backup_dir: string
    stow_script: string
] {
    let target2 = ($test_base | path join "target2")
    mkdir $target2
    "OLD VIMRC CONTENT" | save ($target2 | path join ".vimrc")
    let apply_basic = (
        run-stow-cmd $stow_script apply "vim"
            --target $target2
            --source-dir $source_dir
            --backup-dir $backup_dir
    )
    let vim_backup_scope = (backup-scope $backup_dir "vim" $target2)
    let vim_backups = (
        find-files $vim_backup_scope
        | where { |p| (($p | path basename) | str starts-with ".vimrc-") }
    )
    let vim_backup_content = if ($vim_backups | is-empty) {
        ""
    } else {
        open ($vim_backups | first)
    }

    let target3 = ($test_base | path join "target3")
    mkdir $target3
    ^ln -sf "/dummy" ($target3 | path join ".vimrc")
    let apply_replace = (
        run-stow-cmd $stow_script apply "vim"
            --target $target3
            --source-dir $source_dir
            --backup-dir $backup_dir
    )

    let target4 = ($test_base | path join "target4")
    mkdir $target4
    mkdir ($target4 | path join ".vimrc")
    let apply_dir = (
        run-stow-cmd $stow_script apply "vim"
            --target $target4
            --source-dir $source_dir
            --backup-dir $backup_dir
    )
    let apply_missing = (
        run-stow-cmd $stow_script apply "imaginary"
            --target $target2
            --source-dir $source_dir
            --backup-dir $backup_dir
    )

    # Snapshot state before restore mutates the filesystem
    let t2_vimrc = ($target2 | path join ".vimrc")
    let t3_vimrc = ($target3 | path join ".vimrc")
    let snap_t2_type = (path-type $t2_vimrc)
    let snap_t3_link = (readlink-path $t3_vimrc)

    let restore_basic = (
        run-stow-cmd $stow_script restore "vim"
            --target $target2
            --source-dir $source_dir
            --backup-dir $backup_dir
    )
    [
        (check
            "apply exits cleanly"
            ($apply_basic.exit_code == 0)
            $apply_basic.stderr)
        (check
            "apply creates package backup"
            (not ($vim_backups | is-empty))
            "no backup found")
        (check
            "apply symlinks target"
            ($snap_t2_type == "symlink")
            $snap_t2_type)
        (check
            "apply backup content matches"
            ($vim_backup_content == "OLD VIMRC CONTENT")
            "backup mismatch")
        (check
            "apply over existing symlink exits cleanly"
            ($apply_replace.exit_code == 0)
            $apply_replace.stderr)
        (check
            "apply replaces existing symlink"
            ($snap_t3_link | str contains "/source/vim/")
            $snap_t3_link)
        (check
            "apply fails on directory collision"
            ($apply_dir.exit_code != 0)
            $apply_dir.stderr)
        (check
            "apply missing package fails non-zero"
            ($apply_missing.exit_code != 0)
            $apply_missing.stderr)
        (check
            "restore exits cleanly"
            ($restore_basic.exit_code == 0)
            $restore_basic.stderr)
        (check
            "restore recreates real file"
            ((path-type $t2_vimrc) == "file")
            (path-type $t2_vimrc))
        (check
            "restore recovers original content"
            ((open $t2_vimrc) == "OLD VIMRC CONTENT")
            "restore mismatch")
    ]
}

def test_remove_and_status [
    test_base: string
    source_dir: string
    backup_dir: string
    stow_script: string
] {
    let target_remove = ($test_base | path join "target-remove")
    mkdir $target_remove
    "REMOVE ORIGINAL" | save ($target_remove | path join ".vimrc")
    let apply_remove = (
        run-stow-cmd $stow_script apply "vim"
            --target $target_remove
            --source-dir $source_dir
            --backup-dir $backup_dir
    )
    let remove_basic = (
        run-stow-cmd $stow_script remove "vim"
            --target $target_remove
            --source-dir $source_dir
            --backup-dir $backup_dir
    )

    let target_remove_clean = ($test_base | path join "target-remove-clean")
    mkdir $target_remove_clean
    let apply_remove_clean = (
        run-stow-cmd $stow_script apply "vim"
            --target $target_remove_clean
            --source-dir $source_dir
            --backup-dir $backup_dir
    )
    let remove_clean = (
        run-stow-cmd $stow_script remove "vim"
            --target $target_remove_clean
            --source-dir $source_dir
            --backup-dir $backup_dir
    )

    let target_status_ok = ($test_base | path join "target-status-ok")
    mkdir $target_status_ok
    let apply_status_ok = (
        run-stow-cmd $stow_script apply "vim"
            --target $target_status_ok
            --source-dir $source_dir
            --backup-dir $backup_dir
    )
    let status_ok = (
        run-stow-cmd $stow_script status "vim"
            --target $target_status_ok
            --source-dir $source_dir
            --backup-dir $backup_dir
    )
    let doctor_ok = (
        run-stow-cmd $stow_script doctor "vim"
            --target $target_status_ok
            --source-dir $source_dir
            --backup-dir $backup_dir
    )
    let status_ok_expr = (
        "use '" + $stow_script + "' *; "
        + "(main status vim --target '" + $target_status_ok + "' "
        + "--source-dir '" + $source_dir + "' "
        + "--backup-dir '" + $backup_dir + "') "
        + "| all { |r| $r.state == 'managed' }"
    )
    let status_ok_structured = (run-inline $status_ok_expr)

    let tr_vimrc = ($target_remove | path join ".vimrc")
    let trc_vimrc = ($target_remove_clean | path join ".vimrc")
    [
        (check
            "apply for remove-with-backup exits cleanly"
            ($apply_remove.exit_code == 0)
            $apply_remove.stderr)
        (check
            "remove restores backup content"
            (
                ($remove_basic.exit_code == 0)
                and ((open $tr_vimrc) == "REMOVE ORIGINAL")
            )
            $remove_basic.stderr)
        (check
            "remove restores real file"
            ((path-type $tr_vimrc) == "file")
            (path-type $tr_vimrc))
        (check
            "apply for remove-without-backup exits cleanly"
            ($apply_remove_clean.exit_code == 0)
            $apply_remove_clean.stderr)
        (check
            "remove without backup exits cleanly"
            ($remove_clean.exit_code == 0)
            $remove_clean.stderr)
        (check
            "remove without backup deletes managed symlink"
            (not ($trc_vimrc | path exists))
            $trc_vimrc)
        (check
            "apply for status-ok test exits cleanly"
            ($apply_status_ok.exit_code == 0)
            $apply_status_ok.stderr)
        (check
            "status reports managed target"
            (
                ($status_ok_structured.exit_code == 0)
                and (($status_ok_structured.stdout | str trim) == "true")
            )
            $status_ok_structured.stderr)
        (check
            "doctor exits cleanly for managed target"
            ($doctor_ok.exit_code == 0)
            ($doctor_ok.stdout + $doctor_ok.stderr))
    ]
}

def test_edge_cases [
    test_base: string
    source_dir: string
    backup_dir: string
    stow_script: string
] {
    let collision_root = ($test_base | path join "collision-root")
    mkdir $collision_root
    let collision_base = (
        $collision_root | path join ".vimrc-20260101_010101"
    )
    "first" | save $collision_base
    let next_collision = (run-inline (
        "source '" + $stow_script + "'; "
        + "backup-path '" + $collision_root + "' "
        + "'.vimrc' '20260101_010101'"
    ))
    let next_collision_out = ($next_collision.stdout | lines | last | str trim)

    let to_name = (run-inline $"source '($stow_script)'; to-stow-name '.config'")
    let from_name = (
        run-inline $"source '($stow_script)'; from-stow-name 'dot-config'"
    )

    mkdir ($source_dir | path join "multi/dot-config/app")
    "config-a content" | save (
        $source_dir | path join "multi/dot-config/app/config-a.toml"
    )
    "config-b content" | save (
        $source_dir | path join "multi/dot-config/app/config-b.toml"
    )
    "profile content" | save ($source_dir | path join "multi/dot-profile")
    let target_multi = ($test_base | path join "target-multi")
    mkdir $target_multi
    let apply_multi = (
        run-stow-cmd $stow_script apply "multi"
            --target $target_multi
            --source-dir $source_dir
            --backup-dir $backup_dir
    )
    let doctor_multi = (
        run-stow-cmd $stow_script doctor "multi"
            --target $target_multi
            --source-dir $source_dir
            --backup-dir $backup_dir
    )
    # Snapshot symlink state before remove mutates the filesystem
    let config_a = ($target_multi | path join ".config/app/config-a.toml")
    let config_b = ($target_multi | path join ".config/app/config-b.toml")
    let profile = ($target_multi | path join ".profile")
    let snap_config_a_type = (path-type $config_a)
    let snap_config_b_type = (path-type $config_b)
    let snap_profile_type = (path-type $profile)

    let remove_multi = (
        run-stow-cmd $stow_script remove "multi"
            --target $target_multi
            --source-dir $source_dir
            --backup-dir $backup_dir
    )

    let collision_expected = (
        $collision_root | path join ".vimrc-20260101_010101"
    )
    [
        (check
            "backup-path uses timestamp-only name"
            (
                ($next_collision.exit_code == 0)
                and ($next_collision_out == $collision_expected)
            )
            ($next_collision.stdout + $next_collision.stderr))
        (check
            "to-stow-name works"
            (
                ($to_name.exit_code == 0)
                and ((($to_name.stdout | lines | last | str trim)) == "dot-config")
            )
            $to_name.stdout)
        (check
            "from-stow-name works"
            (
                ($from_name.exit_code == 0)
                and ((($from_name.stdout | lines | last | str trim)) == ".config")
            )
            $from_name.stdout)
        (check
            "apply multi-file package exits cleanly"
            ($apply_multi.exit_code == 0)
            $apply_multi.stderr)
        (check
            "apply multi-file creates first symlink"
            ($snap_config_a_type == "symlink")
            $snap_config_a_type)
        (check
            "apply multi-file creates second symlink"
            ($snap_config_b_type == "symlink")
            $snap_config_b_type)
        (check
            "apply multi-file creates dot-prefixed symlink"
            ($snap_profile_type == "symlink")
            $snap_profile_type)
        (check
            "doctor passes for multi-file package"
            ($doctor_multi.exit_code == 0)
            ($doctor_multi.stdout + $doctor_multi.stderr))
        (check
            "remove multi-file package exits cleanly"
            ($remove_multi.exit_code == 0)
            $remove_multi.stderr)
        (check
            "remove multi-file removes first link"
            (not ($config_a | path exists))
            "still exists")
        (check
            "remove multi-file removes second link"
            (not ($config_b | path exists))
            "still exists")
        (check
            "remove multi-file removes dot-prefixed link"
            (not ($profile | path exists))
            "still exists")
    ]
}

def test_remove_validations [
    test_base: string
    source_dir: string
    backup_dir: string
    stow_script: string
] {
    let target_missing_pkg = ($test_base | path join "target-remove-missing-pkg")
    mkdir $target_missing_pkg
    let remove_missing_pkg = (
        run-stow-cmd $stow_script remove "ghost"
            --target $target_missing_pkg
            --source-dir $source_dir
            --backup-dir $backup_dir
    )

    let target_drift_file = ($test_base | path join "target-drift-file")
    mkdir $target_drift_file
    let drift_file_path = ($target_drift_file | path join ".vimrc")
    "drift start" | save $drift_file_path
    let apply_drift_file = (
        run-stow-cmd $stow_script apply "vim"
            --target $target_drift_file
            --source-dir $source_dir
            --backup-dir $backup_dir
    )
    ^rm -f $drift_file_path
    "drifted content" | save $drift_file_path
    let remove_drift_file = (
        run-stow-cmd $stow_script remove "vim"
            --target $target_drift_file
            --source-dir $source_dir
            --backup-dir $backup_dir
    )

    let target_drift_link = ($test_base | path join "target-drift-link")
    mkdir $target_drift_link
    let apply_drift_link = (
        run-stow-cmd $stow_script apply "vim"
            --target $target_drift_link
            --source-dir $source_dir
            --backup-dir $backup_dir
    )
    let drift_link_path = ($target_drift_link | path join ".vimrc")
    let foreign_file = ($test_base | path join "foreign-file")
    "foreign content" | save $foreign_file
    ^rm -f $drift_link_path
    ^ln -sf $foreign_file $drift_link_path
    let remove_drift_link = (
        run-stow-cmd $stow_script remove "vim"
            --target $target_drift_link
            --source-dir $source_dir
            --backup-dir $backup_dir
    )

    let target_drift_dir = ($test_base | path join "target-drift-dir")
    mkdir $target_drift_dir
    let apply_drift_dir = (
        run-stow-cmd $stow_script apply "vim"
            --target $target_drift_dir
            --source-dir $source_dir
            --backup-dir $backup_dir
    )
    let drift_dir_path = ($target_drift_dir | path join ".vimrc")
    if ($drift_dir_path | path exists) {
        ^rm -rf $drift_dir_path
    }
    mkdir $drift_dir_path
    let remove_dir_block = (
        run-stow-cmd $stow_script remove "vim"
            --target $target_drift_dir
            --source-dir $source_dir
            --backup-dir $backup_dir
    )

    let target_invalid_backup = ($test_base | path join "target-invalid-backup")
    mkdir $target_invalid_backup
    let apply_invalid_backup = (
        run-stow-cmd $stow_script apply "vim"
            --target $target_invalid_backup
            --source-dir $source_dir
            --backup-dir $backup_dir
    )
    let invalid_scope = (backup-scope $backup_dir "vim" $target_invalid_backup)
    if not ($invalid_scope | path exists) {
        mkdir $invalid_scope
    }
    let invalid_file = ($invalid_scope | path join ".vimrc-invalid")
    "invalid backup" | save $invalid_file
    let remove_invalid_backup = (
        run-stow-cmd $stow_script remove "vim"
            --target $target_invalid_backup
            --source-dir $source_dir
            --backup-dir $backup_dir
    )

    [
        (check
            "remove missing package fails"
            ($remove_missing_pkg.exit_code != 0)
            $remove_missing_pkg.stderr)
        (check
            "apply drifted file setup succeeds"
            ($apply_drift_file.exit_code == 0)
            $apply_drift_file.stderr)
        (check
            "remove rejects drifted file target"
            ($remove_drift_file.exit_code != 0)
            $remove_drift_file.stderr)
        (check
            "apply drifted foreign link setup succeeds"
            ($apply_drift_link.exit_code == 0)
            $apply_drift_link.stderr)
        (check
            "remove rejects foreign symlink target"
            ($remove_drift_link.exit_code != 0)
            $remove_drift_link.stderr)
        (check
            "apply directory drift setup succeeds"
            ($apply_drift_dir.exit_code == 0)
            $apply_drift_dir.stderr)
        (check
            "remove rejects directory target"
            ($remove_dir_block.exit_code != 0)
            $remove_dir_block.stderr)
        (check
            "apply invalid backup setup succeeds"
            ($apply_invalid_backup.exit_code == 0)
            $apply_invalid_backup.stderr)
        (check
            "remove fails on invalid backup metadata"
            ($remove_invalid_backup.exit_code != 0)
            $remove_invalid_backup.stderr)
    ]
}

def test_status_and_doctor_states [
    test_base: string
    source_dir: string
    backup_dir: string
    stow_script: string
] {
    let target_status = ($test_base | path join "target-status-matrix")
    mkdir $target_status

    let managed_path = ($target_status | path join ".managed")
    let missing_path = ($target_status | path join ".missing")
    let file_path = ($target_status | path join ".file")
    let dir_path = ($target_status | path join ".directory")
    let foreign_path = ($target_status | path join ".foreign")
    let invalid_path = ($target_status | path join ".invalid")

    "managed original" | save $managed_path
    "missing original" | save $missing_path
    "file original" | save $file_path
    "dir original" | save $dir_path
    "foreign original" | save $foreign_path
    "invalid original" | save $invalid_path

    let add_managed = (
        run-stow-cmd $stow_script add "states" $managed_path
            --target $target_status
            --source-dir $source_dir
    )
    let add_missing = (
        run-stow-cmd $stow_script add "states" $missing_path
            --target $target_status
            --source-dir $source_dir
    )
    let add_file = (
        run-stow-cmd $stow_script add "states" $file_path
            --target $target_status
            --source-dir $source_dir
    )
    let add_dir = (
        run-stow-cmd $stow_script add "states" $dir_path
            --target $target_status
            --source-dir $source_dir
    )
    let add_foreign = (
        run-stow-cmd $stow_script add "states" $foreign_path
            --target $target_status
            --source-dir $source_dir
    )
    let add_invalid = (
        run-stow-cmd $stow_script add "states" $invalid_path
            --target $target_status
            --source-dir $source_dir
    )

    ^rm -f $managed_path
    "managed drift" | save $managed_path
    ^rm -f $invalid_path
    let apply_states = (
        run-stow-cmd $stow_script apply "states"
            --target $target_status
            --source-dir $source_dir
            --backup-dir $backup_dir
    )

    ^rm -f $missing_path
    ^rm -f $file_path
    "new real file" | save $file_path
    if ($dir_path | path exists) {
        ^rm -rf $dir_path
    }
    mkdir $dir_path
    let foreign_real = ($test_base | path join "foreign-real")
    "foreign data" | save $foreign_real
    ^rm -f $foreign_path
    ^ln -sf $foreign_real $foreign_path

    let states_backup_scope = (backup-scope $backup_dir "states" $target_status)
    if not ($states_backup_scope | path exists) {
        mkdir $states_backup_scope
    }
    let invalid_backup = ($states_backup_scope | path join ".invalid-INVALID")
    "invalid" | save $invalid_backup

    let status_expr = (
        "use '" + $stow_script + "' *; "
        + "(main status states --target '" + $target_status + "' "
        + "--source-dir '" + $source_dir + "' "
        + "--backup-dir '" + $backup_dir + "') | to json"
    )
    let status_json = (run-inline $status_expr)
    let status_records = if ($status_json.exit_code == 0) {
        $status_json.stdout | from json
    } else {
        []
    }
    let status_root = ($target_status | path expand)
    let managed_key = ($status_root | path join ".managed")
    let missing_key = ($status_root | path join ".missing")
    let file_key = ($status_root | path join ".file")
    let dir_key = ($status_root | path join ".directory")
    let foreign_key = ($status_root | path join ".foreign")
    let invalid_key = ($status_root | path join ".invalid")
    let foreign_link = $foreign_real

    let managed_record = (
        $status_records
        | where { |row| $row.target == $managed_key }
        | first
        | default {
            state: ""
            backup_status: ""
            backup_path: ""
            link_target: ""
        }
    )
    let missing_record = (
        $status_records
        | where { |row| $row.target == $missing_key }
        | first
        | default { state: "" backup_status: "" link_target: "" }
    )
    let file_record = (
        $status_records
        | where { |row| $row.target == $file_key }
        | first
        | default { state: "" backup_status: "" link_target: "" }
    )
    let dir_record = (
        $status_records
        | where { |row| $row.target == $dir_key }
        | first
        | default { state: "" backup_status: "" link_target: "" }
    )
    let foreign_record = (
        $status_records
        | where { |row| $row.target == $foreign_key }
        | first
        | default { state: "" backup_status: "" link_target: "" }
    )
    let invalid_record = (
        $status_records
        | where { |row| $row.target == $invalid_key }
        | first
        | default { state: "" backup_status: "" link_target: "" }
    )

    let doctor_fail = (
        run-stow-cmd $stow_script doctor "states"
            --target $target_status
            --source-dir $source_dir
            --backup-dir $backup_dir
    )

    [
        (check
            "add states managed target succeeds"
            ($add_managed.exit_code == 0)
            $add_managed.stderr)
        (check
            "add states missing target succeeds"
            ($add_missing.exit_code == 0)
            $add_missing.stderr)
        (check
            "status managed record shows backup found"
            (
                ($status_json.exit_code == 0)
                and ($managed_record.state == "managed")
                and ($managed_record.backup_status == "found")
                and (not ($managed_record.backup_path | is-empty))
            )
            "managed status mismatch")
        (check
            "status missing record detected"
            (
                ($missing_record.state == "missing")
                and ($missing_record.backup_status == "missing")
            )
            "missing status mismatch")
        (check
            "status detects drifted file"
            (
                ($file_record.state == "file")
                and ($file_record.backup_status == "missing")
            )
            "file status mismatch")
        (check
            "status detects directory collision"
            (
                ($dir_record.state == "directory")
                and ($dir_record.backup_status == "missing")
            )
            "directory status mismatch")
        (check
            "status detects foreign symlink"
            (
                ($foreign_record.state == "foreign-symlink")
                and ($foreign_record.backup_status == "missing")
                and ($foreign_record.link_target == $foreign_link)
            )
            "foreign status mismatch")
        (check
            "status reports invalid backup metadata"
            (
                ($invalid_record.backup_status == "invalid")
                and ($invalid_record.state == "managed")
            )
            "invalid backup status mismatch")
        (check
            "doctor fails when targets unhealthy"
            ($doctor_fail.exit_code != 0)
            ($doctor_fail.stdout + $doctor_fail.stderr))
    ]
}

def test_restore_boundaries [
    test_base: string
    source_dir: string
    backup_dir: string
    stow_script: string
] {
    let restore_seed = ($test_base | path join "target-restore-seed")
    mkdir $restore_seed
    let seed_file = ($restore_seed | path join ".restore")
    "restore seed content" | save $seed_file
    let add_restorepkg = (
        run-stow-cmd $stow_script add "restorepkg" $seed_file
            --target $restore_seed
            --source-dir $source_dir
    )

    let target_restore_missing_pkg = ($test_base | path join "target-restore-missing-pkg")
    mkdir $target_restore_missing_pkg
    let restore_missing_pkg = (
        run-stow-cmd $stow_script restore "ghost"
            --target $target_restore_missing_pkg
            --source-dir $source_dir
            --backup-dir $backup_dir
    )

    let target_restore_file = ($test_base | path join "target-restore-file")
    mkdir $target_restore_file
    let apply_restore_file = (
        run-stow-cmd $stow_script apply "restorepkg"
            --target $target_restore_file
            --source-dir $source_dir
            --backup-dir $backup_dir
    )
    let restore_file_path = ($target_restore_file | path join ".restore")
    ^rm -f $restore_file_path
    "manual edit" | save $restore_file_path
    let restore_fail_file = (
        run-stow-cmd $stow_script restore "restorepkg"
            --target $target_restore_file
            --source-dir $source_dir
            --backup-dir $backup_dir
    )

    let target_restore_symlink = ($test_base | path join "target-restore-symlink")
    mkdir $target_restore_symlink
    let apply_restore_symlink = (
        run-stow-cmd $stow_script apply "restorepkg"
            --target $target_restore_symlink
            --source-dir $source_dir
            --backup-dir $backup_dir
    )
    let restore_symlink = (
        run-stow-cmd $stow_script restore "restorepkg"
            --target $target_restore_symlink
            --source-dir $source_dir
            --backup-dir $backup_dir
    )

    let target_restore_missing = ($test_base | path join "target-restore-missing")
    mkdir $target_restore_missing
    let apply_restore_missing = (
        run-stow-cmd $stow_script apply "restorepkg"
            --target $target_restore_missing
            --source-dir $source_dir
            --backup-dir $backup_dir
    )
    let missing_restore_path = ($target_restore_missing | path join ".restore")
    ^rm -f $missing_restore_path
    let restore_missing_target = (
        run-stow-cmd $stow_script restore "restorepkg"
            --target $target_restore_missing
            --source-dir $source_dir
            --backup-dir $backup_dir
    )

    let target_restore_dir = ($test_base | path join "target-restore-dir")
    mkdir $target_restore_dir
    let dir_restore_path = ($target_restore_dir | path join ".restore")
    "dir original" | save $dir_restore_path
    let apply_restore_dir = (
        run-stow-cmd $stow_script apply "restorepkg"
            --target $target_restore_dir
            --source-dir $source_dir
            --backup-dir $backup_dir
    )
    ^rm -f $dir_restore_path
    mkdir $dir_restore_path
    let restore_dir_collision = (
        run-stow-cmd $stow_script restore "restorepkg"
            --target $target_restore_dir
            --source-dir $source_dir
            --backup-dir $backup_dir
    )

    let target_restore_latest = ($test_base | path join "target-restore-latest")
    mkdir $target_restore_latest
    let restore_latest_path = ($target_restore_latest | path join ".restore")
    if ($restore_latest_path | path exists) {
        ^rm -rf $restore_latest_path
    }
    let latest_scope = (backup-scope $backup_dir "restorepkg" $target_restore_latest)
    if not ($latest_scope | path exists) {
        mkdir $latest_scope
    }
    let backup_old = ($latest_scope | path join ".restore-20260101_010101")
    let backup_new = ($latest_scope | path join ".restore-20260101_020202")
    "older" | save $backup_old
    "newer" | save $backup_new
    let restore_latest = (
        run-stow-cmd $stow_script restore "restorepkg"
            --target $target_restore_latest
            --source-dir $source_dir
            --backup-dir $backup_dir
    )

    [
        (check
            "restore package staging succeeds"
            ($add_restorepkg.exit_code == 0)
            $add_restorepkg.stderr)
        (check
            "restore missing package fails"
            ($restore_missing_pkg.exit_code != 0)
            $restore_missing_pkg.stderr)
        (check
            "restore rejects file without backup"
            ($restore_fail_file.exit_code != 0)
            $restore_fail_file.stderr)
        (check
            "restore warns but succeeds for unmanaged symlink"
            (
                ($apply_restore_symlink.exit_code == 0)
                and ($restore_symlink.exit_code == 0)
            )
            ($apply_restore_symlink.stderr + $restore_symlink.stderr))
        (check
            "restore warns but succeeds for missing target"
            (
                ($apply_restore_missing.exit_code == 0)
                and ($restore_missing_target.exit_code == 0)
            )
            ($restore_missing_target.stderr))
        (check
            "restore fails on directory collision"
            ($restore_dir_collision.exit_code != 0)
            $restore_dir_collision.stderr)
        (check
            "restore chooses newest backup content"
            (
                ($restore_latest.exit_code == 0)
                and ((open $restore_latest_path) == "newer")
            )
            $restore_latest.stderr)
    ]
}

def test_preflight_atomicity [
    test_base: string
    source_dir: string
    backup_dir: string
    stow_script: string
] {
    mkdir ($source_dir | path join "atomic")
    "atomic a" | save ($source_dir | path join "atomic/dot-a")
    "atomic z" | save ($source_dir | path join "atomic/dot-z")

    let target_apply = ($test_base | path join "target-atomic-apply")
    mkdir $target_apply
    let apply_a = ($target_apply | path join ".a")
    let apply_z = ($target_apply | path join ".z")
    "apply original a" | save $apply_a
    mkdir $apply_z
    let apply_atomic = (
        run-stow-cmd $stow_script apply "atomic"
            --target $target_apply
            --source-dir $source_dir
            --backup-dir $backup_dir
    )
    let apply_scope = (backup-scope $backup_dir "atomic" $target_apply)
    let apply_a_backup = (
        find-files $apply_scope
        | where { |p| (($p | path basename) | str starts-with ".a-") }
    )

    let target_remove = ($test_base | path join "target-atomic-remove")
    mkdir $target_remove
    let remove_a = ($target_remove | path join ".a")
    let remove_z = ($target_remove | path join ".z")
    "remove original a" | save $remove_a
    "remove original z" | save $remove_z
    let apply_remove_setup = (
        run-stow-cmd $stow_script apply "atomic"
            --target $target_remove
            --source-dir $source_dir
            --backup-dir $backup_dir
    )
    if ($remove_z | path exists) {
        ^rm -f $remove_z
    }
    mkdir $remove_z
    let remove_atomic = (
        run-stow-cmd $stow_script remove "atomic"
            --target $target_remove
            --source-dir $source_dir
            --backup-dir $backup_dir
    )

    let target_restore = ($test_base | path join "target-atomic-restore")
    mkdir $target_restore
    let restore_a = ($target_restore | path join ".a")
    let restore_z = ($target_restore | path join ".z")
    "restore original a" | save $restore_a
    "restore original z" | save $restore_z
    let apply_restore_setup = (
        run-stow-cmd $stow_script apply "atomic"
            --target $target_restore
            --source-dir $source_dir
            --backup-dir $backup_dir
    )
    if ($restore_z | path exists) {
        ^rm -f $restore_z
    }
    mkdir $restore_z
    let restore_atomic = (
        run-stow-cmd $stow_script restore "atomic"
            --target $target_restore
            --source-dir $source_dir
            --backup-dir $backup_dir
    )

    [
        (check
            "apply preflight failure exits non-zero"
            ($apply_atomic.exit_code != 0)
            $apply_atomic.stderr)
        (check
            "apply preflight keeps earlier file untouched"
            (
                ((path-type $apply_a) == "file")
                and ((open $apply_a) == "apply original a")
            )
            "apply mutated earlier target")
        (check
            "apply preflight skips backup creation"
            ($apply_a_backup | is-empty)
            "backup created before apply failed")
        (check
            "remove atomic setup succeeds"
            ($apply_remove_setup.exit_code == 0)
            $apply_remove_setup.stderr)
        (check
            "remove preflight failure exits non-zero"
            ($remove_atomic.exit_code != 0)
            $remove_atomic.stderr)
        (check
            "remove preflight keeps earlier symlink managed"
            (
                ((path-type $remove_a) == "symlink")
                and ((readlink-path $remove_a) | str contains "/source/atomic/")
            )
            "remove mutated earlier target")
        (check
            "restore atomic setup succeeds"
            ($apply_restore_setup.exit_code == 0)
            $apply_restore_setup.stderr)
        (check
            "restore preflight failure exits non-zero"
            ($restore_atomic.exit_code != 0)
            $restore_atomic.stderr)
        (check
            "restore preflight keeps earlier symlink managed"
            (
                ((path-type $restore_a) == "symlink")
                and ((readlink-path $restore_a) | str contains "/source/atomic/")
            )
            "restore mutated earlier target")
    ]
}

def main [] {
    let now = (date now | format date "%Y%m%d_%H%M%S")
    let test_base = (
        $env.TMPDIR? | default "/tmp" | path join $"stow-test-($now)"
    )
    let source_dir = ($test_base | path join "source")
    let target_dir = ($test_base | path join "target")
    let backup_dir = ($test_base | path join "backups")
    let stow_script = (
        $env.FILE_PWD | path join ".." "stow.nu" | path expand
    )

    mkdir $test_base
    mkdir $source_dir
    mkdir $target_dir
    mkdir $backup_dir
    mkdir ($test_base | path join ".linux-config-logs")
    load-env { HOME: $test_base }

    mut checks = []
    log+ $"Test directory: ($test_base)"

    $checks ++= (
        test_add_basic $test_base $source_dir $target_dir $stow_script
    )
    $checks ++= (
        test_add_executable $test_base $source_dir $target_dir $stow_script
    )
    $checks ++= (
        test_add_nested $test_base $source_dir $target_dir $stow_script
    )
    $checks ++= (
        test_apply_and_restore $test_base $source_dir $backup_dir $stow_script
    )
    $checks ++= (
        test_remove_and_status $test_base $source_dir $backup_dir $stow_script
    )
    $checks ++= (
        test_edge_cases $test_base $source_dir $backup_dir $stow_script
    )
    $checks ++= (
        test_remove_validations $test_base $source_dir $backup_dir $stow_script
    )
    $checks ++= (
        test_status_and_doctor_states $test_base $source_dir $backup_dir $stow_script
    )
    $checks ++= (
        test_restore_boundaries $test_base $source_dir $backup_dir $stow_script
    )
    $checks ++= (
        test_preflight_atomicity $test_base $source_dir $backup_dir $stow_script
    )

    let failed = ($checks | where { |item| not $item.passed })
    print ""
    let total = ($checks | length)
    let n_failed = ($failed | length)
    print $"Summary: ($total - $n_failed) passed, ($n_failed) failed"
    do -i { ^rm -rf $test_base }
    if (not ($failed | is-empty)) { exit 1 }
}

main
