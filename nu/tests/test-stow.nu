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
        "source '" + $stow_script + "'; "
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
    let collision_one = (
        $collision_root | path join ".vimrc-20260101_010101-1"
    )
    "first" | save $collision_base
    "second" | save $collision_one
    let next_collision = (run-inline (
        "source " + $stow_script + "; "
        + "unique-backup-path '" + $collision_root + "' "
        + "'.vimrc' '20260101_010101'"
    ))
    let next_collision_out = ($next_collision.stdout | str trim)

    let to_name = (run-inline $"source ($stow_script); to-stow-name '.config'")
    let from_name = (
        run-inline $"source ($stow_script); from-stow-name 'dot-config'"
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
        $collision_root | path join ".vimrc-20260101_010101-2"
    )
    [
        (check
            "unique-backup-path adds collision suffix"
            (
                ($next_collision.exit_code == 0)
                and ($next_collision_out == $collision_expected)
            )
            ($next_collision.stdout + $next_collision.stderr))
        (check
            "to-stow-name works"
            (
                ($to_name.exit_code == 0)
                and (($to_name.stdout | str trim) == "dot-config")
            )
            $to_name.stdout)
        (check
            "from-stow-name works"
            (
                ($from_name.exit_code == 0)
                and (($from_name.stdout | str trim) == ".config")
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

    let failed = ($checks | where { |item| not $item.passed })
    print ""
    let total = ($checks | length)
    let n_failed = ($failed | length)
    print $"Summary: ($total - $n_failed) passed, ($n_failed) failed"
    do -i { ^rm -rf $test_base }
    if (not ($failed | is-empty)) { exit 1 }
}

main