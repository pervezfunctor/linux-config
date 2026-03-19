#!/usr/bin/env nu

use std/log

def log+ [msg: string] { log info $msg }

def detect-path-kind [path: string] {
    do -i { $path | path type } | default "none"
}

def read-symlink-target [path: string] {
    do -i { ^readlink $path } | default ""
}

def is-executable-file [path: string] {
    let result = (^bash -lc 'test -x "$1"' _ $path | complete)
    $result.exit_code == 0
}

def encode-dot-segment [name: string] {
    if ($name | str starts-with ".") {
        $"dot-($name | str substring 1..)"
    } else {
        $name
    }
}

def build-expected-backup-path [
    backup_dir: string
    package: string
    target_root: string
    target_path: string
] {
    let abs_root = ($target_root | path expand)
    let abs_path = (
        if ($target_path | str starts-with "/") {
            $target_path | path expand --no-symlink
        } else {
            ($abs_root | path join $target_path) | path expand --no-symlink
        }
    )
    let scope = (
        $abs_root
        | path split
        | each { |part|
            if $part in ["", "/"] { "_root_" } else { encode-dot-segment $part }
        }
    )
    let rel = ($abs_path | str substring (($abs_root | str length) + 1)..)
    let base = ($backup_dir | path join $package | path join ...$scope)
    $"($base)/($rel)"
}

def assert-check [name: string, passed: bool, detail: string] {
    print $"(if $passed { '[PASS]' } else { '[FAIL]' }) ($name)"
    if not $passed { print $"  Detail: ($detail)" }
    { name: $name, passed: $passed, detail: $detail }
}

def --wrapped run-script-command [stow_script: string, ...args: string] {
    ^nu -n $stow_script ...$args | complete
}

def run-inline-nu [expr: string] {
    ^nu -n -c $expr | complete
}

def list-files-under [root: string] {
    let found = (^find $root -type f | complete)
    if $found.exit_code == 0 {
        $found.stdout | lines | where { |line| not ($line | is-empty) }
    } else {
        []
    }
}

def test_add [
    test_base: string
    source_dir: string
    target_dir: string
    stow_script: string
] {
    let basic = ($target_dir | path join ".vimrc")
    "vimrc content" | save $basic
    let add_basic = (
        run-script-command $stow_script add vim $basic
            --target $target_dir
            --source-dir $source_dir
    )
    let staged_basic = ($source_dir | path join "vim/dot-vimrc")
    let basic_content_after_add = (open $basic)

    mkdir ($target_dir | path join ".local/bin")
    let exec_target = ($target_dir | path join ".local/bin/demo")
    "#!/usr/bin/env bash\necho demo" | save $exec_target
    ^chmod 755 $exec_target
    let add_exec = (
        run-script-command $stow_script add bin $exec_target
            --target $target_dir
            --source-dir $source_dir
    )
    let staged_exec = ($source_dir | path join "bin/dot-local/bin/demo")

    mkdir ($target_dir | path join ".config/app")
    let nested = ($target_dir | path join ".config/app/init.lua")
    "print('hi')" | save $nested
    let add_nested = (
        run-script-command $stow_script add nvim $nested
            --target $target_dir
            --source-dir $source_dir
    )
    let staged_nested = ($source_dir | path join "nvim/dot-config/app/init.lua")

    "new vimrc content" | save --force $basic
    let add_refresh = (
        run-script-command $stow_script add vim $basic
            --target $target_dir
            --source-dir $source_dir
    )

    let aliases_real = ($test_base | path join "aliases-real")
    "alias ll='ls -la'" | save $aliases_real
    let aliases_link = ($target_dir | path join ".aliases")
    ^ln -sf $aliases_real $aliases_link
    let add_symlink = (
        run-script-command $stow_script add shell $aliases_link
            --target $target_dir
            --source-dir $source_dir
    )

    let config_link = ($target_dir | path join ".config-link")
    ^ln -sf ($target_dir | path join ".config") $config_link
    let add_dir_link = (
        run-script-command $stow_script add shell $config_link
            --target $target_dir
            --source-dir $source_dir
    )

    let broken_real = ($test_base | path join "missing-real")
    let broken_link = ($target_dir | path join ".broken")
    ^ln -sf $broken_real $broken_link
    let add_broken = (
        run-script-command $stow_script add broken $broken_link
            --target $target_dir
            --source-dir $source_dir
    )

    let dir_target = ($target_dir | path join ".dir")
    mkdir $dir_target
    let add_dir = (
        run-script-command $stow_script add bad $dir_target
            --target $target_dir
            --source-dir $source_dir
    )

    let outside = ($test_base | path join "outside.txt")
    "outside" | save $outside
    let add_outside = (
        run-script-command $stow_script add out $outside
            --target $target_dir
            --source-dir $source_dir
    )

    let rel_root = ($test_base | path join "rel")
    mkdir ($rel_root | path join "source")
    mkdir ($rel_root | path join "target")
    "relative content" | save ($rel_root | path join "target/.relrc")
    let rel_add = (run-inline-nu (
        "cd '" + $rel_root + "'; "
        + "nu -n '" + $stow_script + "' add relpkg target/.relrc "
        + "--target target --source-dir source"
    ))
    let rel_staged = ($rel_root | path join "source/relpkg/dot-relrc")
    let rel_target = ($rel_root | path join "target/.relrc")

    [
        (assert-check "add basic exits cleanly" ($add_basic.exit_code == 0)
            $add_basic.stderr)
        (assert-check "add basic stages file" ($staged_basic | path exists)
            $staged_basic)
        (assert-check "add basic creates symlink"
            ((detect-path-kind $basic) == "symlink")
            (detect-path-kind $basic))
        (assert-check "add basic preserves content"
            ($basic_content_after_add == "vimrc content")
            "content mismatch")
        (assert-check "add executable exits cleanly" ($add_exec.exit_code == 0)
            $add_exec.stderr)
        (assert-check "add preserves staged executable bit"
            (is-executable-file $staged_exec)
            $staged_exec)
        (assert-check "add preserves deployed executable bit"
            (is-executable-file $exec_target)
            $exec_target)
        (assert-check "add nested exits cleanly" ($add_nested.exit_code == 0)
            $add_nested.stderr)
        (assert-check "add nested stages dot path"
            ($staged_nested | path exists)
            $staged_nested)
        (assert-check "add refresh rejects already-symlinked target"
            ($add_refresh.exit_code != 0)
            $add_refresh.stderr)
        (assert-check "add refresh updates staged content"
            ((open $staged_basic) == "new vimrc content")
            "stale staged content")
        (assert-check "add rejects symlink to file"
            ($add_symlink.exit_code != 0)
            $add_symlink.stderr)
        (assert-check "add rejects symlink to directory"
            ($add_dir_link.exit_code != 0)
            $add_dir_link.stderr)
        (assert-check "add rejects broken symlink" ($add_broken.exit_code != 0)
            $add_broken.stderr)
        (assert-check "add rejects directories" ($add_dir.exit_code != 0)
            $add_dir.stderr)
        (assert-check "add rejects outside target" ($add_outside.exit_code != 0)
            $add_outside.stderr)
        (assert-check "add relative paths exits cleanly"
            ($rel_add.exit_code == 0)
            $rel_add.stderr)
        (assert-check "add relative path stages file"
            ($rel_staged | path exists)
            $rel_staged)
        (assert-check "add relative path symlinks target"
            ((detect-path-kind $rel_target) == "symlink")
            (detect-path-kind $rel_target))
    ]
}

def test_apply [
    test_base: string
    source_dir: string
    backup_dir: string
    stow_script: string
] {
    mkdir ($source_dir | path join "vimapply")
    "staged vim" | save ($source_dir | path join "vimapply/dot-vimrc")
    mkdir ($source_dir | path join "appapply/dot-config/demo")
    "conf a" | save ($source_dir | path join "appapply/dot-config/demo/a.toml")
    "conf b" | save ($source_dir | path join "appapply/dot-config/demo/b.toml")

    let target_backup = ($test_base | path join "target-backup")
    mkdir $target_backup
    let target_vim = ($target_backup | path join ".vimrc")
    "old vim" | save $target_vim
    let apply_backup = (
        run-script-command $stow_script apply vimapply
            --target $target_backup
            --source-dir $source_dir
            --backup-dir $backup_dir
    )
    let backup_vim = (
        list-files-under ($backup_dir | path join "vimapply")
        | where { |p| ($p | path basename) == ".vimrc" }
        | first
        | default ""
    )

    let target_link = ($test_base | path join "target-link")
    mkdir $target_link
    let link_vim = ($target_link | path join ".vimrc")
    ^ln -sf "/tmp/foreign-target" $link_vim
    let apply_replace_symlink = (
        run-script-command $stow_script apply vimapply
            --target $target_link
            --source-dir $source_dir
            --backup-dir $backup_dir
    )

    let target_dir_collision = ($test_base | path join "target-dir-collision")
    mkdir $target_dir_collision
    mkdir ($target_dir_collision | path join ".vimrc")
    let apply_dir_collision = (
        run-script-command $stow_script apply vimapply
            --target $target_dir_collision
            --source-dir $source_dir
            --backup-dir $backup_dir
    )

    let apply_missing_pkg = (
        run-script-command $stow_script apply ghost
            --target $target_backup
            --source-dir $source_dir
            --backup-dir $backup_dir
    )

    let target_multi = ($test_base | path join "target-multi")
    mkdir $target_multi
    let apply_multi = (
        run-script-command $stow_script apply appapply
            --target $target_multi
            --source-dir $source_dir
            --backup-dir $backup_dir
    )
    let config_a = ($target_multi | path join ".config/demo/a.toml")
    let config_b = ($target_multi | path join ".config/demo/b.toml")

    let target_overwrite = ($test_base | path join "target-overwrite")
    mkdir $target_overwrite
    let overwrite_vim = ($target_overwrite | path join ".vimrc")
    "first original" | save $overwrite_vim
    let apply_first = (
        run-script-command $stow_script apply vimapply
            --target $target_overwrite
            --source-dir $source_dir
            --backup-dir $backup_dir
    )
    ^rm -f $overwrite_vim
    "second original" | save $overwrite_vim
    let apply_second = (
        run-script-command $stow_script apply vimapply
            --target $target_overwrite
            --source-dir $source_dir
            --backup-dir $backup_dir
    )
    let overwrite_backup = (
        list-files-under ($backup_dir | path join "vimapply")
        | where { |p| ($p | path basename) == ".vimrc" }
        | where { |p| $p | str contains "target-overwrite" }
        | first
        | default ""
    )

    [
        (assert-check "apply backs up real file cleanly"
            ($apply_backup.exit_code == 0)
            $apply_backup.stderr)
        (assert-check "apply backup file created" ($backup_vim | path exists)
            $backup_vim)
        (assert-check "apply backup preserves original content"
            ((open $backup_vim) == "old vim")
            "backup mismatch")
        (assert-check "apply replaces target with symlink"
            ((detect-path-kind $target_vim) == "symlink")
            (detect-path-kind $target_vim))
        (assert-check "apply symlink points into package"
            ((read-symlink-target $target_vim) | str contains "vimapply")
            (read-symlink-target $target_vim))
        (assert-check "apply replaces existing foreign symlink"
            ($apply_replace_symlink.exit_code == 0)
            $apply_replace_symlink.stderr)
        (assert-check "apply removes previous symlink without backup"
            (
                list-files-under ($backup_dir | path join "vimapply")
                | where { |p| $p | str contains "target-link" }
                | is-empty
            )
            "unexpected backup for symlink")
        (assert-check "apply foreign symlink becomes managed"
            ((read-symlink-target $link_vim) | str contains "vimapply")
            (read-symlink-target $link_vim))
        (assert-check "apply fails on directory collision"
            ($apply_dir_collision.exit_code != 0)
            $apply_dir_collision.stderr)
        (assert-check "apply missing package fails"
            ($apply_missing_pkg.exit_code != 0)
            $apply_missing_pkg.stderr)
        (assert-check "apply multi-file package exits cleanly"
            ($apply_multi.exit_code == 0)
            $apply_multi.stderr)
        (assert-check "apply multi creates first file symlink"
            ((detect-path-kind $config_a) == "symlink")
            (detect-path-kind $config_a))
        (assert-check "apply multi creates second file symlink"
            ((detect-path-kind $config_b) == "symlink")
            (detect-path-kind $config_b))
        (assert-check "apply initial overwrite setup succeeds"
            ($apply_first.exit_code == 0)
            $apply_first.stderr)
        (assert-check "apply overwrite updates single backup path"
            (
                $apply_second.exit_code == 0
                and (open $overwrite_backup) == "second original"
            )
            (
                if ($overwrite_backup | path exists) {
                    open $overwrite_backup
                } else {
                    "missing backup"
                }
            ))
    ]
}

def test_restore [
    test_base: string
    source_dir: string
    backup_dir: string
    stow_script: string
] {
    mkdir ($source_dir | path join "restorepkg")
    "restored content" | save ($source_dir | path join "restorepkg/dot-restore")
    let apply_seed_target = ($test_base | path join "seed-target")
    mkdir $apply_seed_target
    let seed_file = ($apply_seed_target | path join ".restore")
    "seed original" | save $seed_file
    let apply_seed = (
        run-script-command $stow_script apply restorepkg
            --target $apply_seed_target
            --source-dir $source_dir
            --backup-dir $backup_dir
    )
    let seed_backup = (
        list-files-under ($backup_dir | path join "restorepkg")
        | where { |p| ($p | path basename) == ".restore" }
        | where { |p| $p | str contains "seed-target" }
        | first
        | default ""
    )

    let restore_missing_pkg = (
        run-script-command $stow_script restore ghost
            --target $apply_seed_target
            --source-dir $source_dir
            --backup-dir $backup_dir
    )

    let target_missing = ($test_base | path join "restore-missing")
    mkdir $target_missing
    let missing_path = ($target_missing | path join ".restore")
    "missing seed" | save $missing_path
    let apply_missing_seed = (
        run-script-command $stow_script apply restorepkg
            --target $target_missing
            --source-dir $source_dir
            --backup-dir $backup_dir
    )
    ^rm -f $missing_path
    let restore_missing = (
        run-script-command $stow_script restore restorepkg
            --target $target_missing
            --source-dir $source_dir
            --backup-dir $backup_dir
    )

    let target_symlink = ($test_base | path join "restore-symlink")
    mkdir $target_symlink
    let symlink_path = ($target_symlink | path join ".restore")
    "symlink seed" | save $symlink_path
    let apply_symlink_seed = (
        run-script-command $stow_script apply restorepkg
            --target $target_symlink
            --source-dir $source_dir
            --backup-dir $backup_dir
    )
    ^ln -sf "/tmp/foreign-restore" $symlink_path
    let restore_symlink = (
        run-script-command $stow_script restore restorepkg
            --target $target_symlink
            --source-dir $source_dir
            --backup-dir $backup_dir
    )

    let target_file = ($test_base | path join "restore-file")
    mkdir $target_file
    let file_path = ($target_file | path join ".restore")
    "file seed" | save $file_path
    let apply_file_seed = (
        run-script-command $stow_script apply restorepkg
            --target $target_file
            --source-dir $source_dir
            --backup-dir $backup_dir
    )
    ^rm -f $file_path
    "drifted file" | save $file_path
    let restore_file = (
        run-script-command $stow_script restore restorepkg
            --target $target_file
            --source-dir $source_dir
            --backup-dir $backup_dir
    )

    let target_none = ($test_base | path join "restore-none")
    mkdir $target_none
    let restore_none = (
        run-script-command $stow_script restore restorepkg
            --target $target_none
            --source-dir $source_dir
            --backup-dir $backup_dir
    )

    let target_dir = ($test_base | path join "restore-dir")
    mkdir $target_dir
    let dir_path = ($target_dir | path join ".restore")
    "dir seed" | save $dir_path
    let apply_dir_seed = (
        run-script-command $stow_script apply restorepkg
            --target $target_dir
            --source-dir $source_dir
            --backup-dir $backup_dir
    )
    ^rm -f $dir_path
    mkdir $dir_path
    let restore_dir = (
        run-script-command $stow_script restore restorepkg
            --target $target_dir
            --source-dir $source_dir
            --backup-dir $backup_dir
    )

    [
        (assert-check "restore seed apply exits cleanly"
            ($apply_seed.exit_code == 0)
            $apply_seed.stderr)
        (assert-check "restore seed backup exists"
            ($seed_backup | path exists)
            $seed_backup)
        (assert-check "restore missing package fails"
            ($restore_missing_pkg.exit_code != 0)
            $restore_missing_pkg.stderr)
        (assert-check "restore setup for missing target succeeds"
            ($apply_missing_seed.exit_code == 0)
            $apply_missing_seed.stderr)
        (assert-check "restore recreates missing target"
            (
                $restore_missing.exit_code == 0
                and (open $missing_path) == "missing seed"
            )
            $restore_missing.stderr)
        (assert-check "restore setup for symlink target succeeds"
            ($apply_symlink_seed.exit_code == 0)
            $apply_symlink_seed.stderr)
        (assert-check "restore replaces symlink with file"
            (
                $restore_symlink.exit_code == 0
                and (detect-path-kind $symlink_path) == "file"
                and (open $symlink_path) == "symlink seed"
            )
            (detect-path-kind $symlink_path))
        (assert-check "restore setup for file target succeeds"
            ($apply_file_seed.exit_code == 0)
            $apply_file_seed.stderr)
        (assert-check "restore replaces file content"
            (
                $restore_file.exit_code == 0
                and (open $file_path) == "file seed"
            )
            $restore_file.stderr)
        (assert-check "restore skips path with no backup"
            (
                $restore_none.exit_code == 0
                and (not (($target_none | path join ".restore") | path exists))
            )
            $restore_none.stderr)
        (assert-check "restore setup for directory collision succeeds"
            ($apply_dir_seed.exit_code == 0)
            $apply_dir_seed.stderr)
        (assert-check "restore fails on directory collision"
            ($restore_dir.exit_code != 0)
            $restore_dir.stderr)
        (assert-check "restore restores applied backup content"
            (
                (
                    run-script-command $stow_script restore restorepkg
                        --target $apply_seed_target
                        --source-dir $source_dir
                        --backup-dir $backup_dir
                ).exit_code == 0
                and (open $seed_file) == "seed original"
            )
            "seed restore mismatch")
    ]
}

def test_helper_exports [stow_script: string] {
    let to_name = (
        run-inline-nu $"source '($stow_script)'; encode-dot-segment '.config'"
    )
    let from_name = (
        run-inline-nu (
            $"source '($stow_script)'; decode-dot-segment 'dot-config'"
        )
    )
    let backup_expr = (
        "source '" + $stow_script + "'; "
        + "build-backup-file-path '/tmp/backups' 'pkg' "
        + "'/tmp/target' '/tmp/target/.vimrc'"
    )
    let backup_out = (run-inline-nu $backup_expr)
    let backup_line = (
        $backup_out.stdout | lines | last | default "" | str trim
    )

    [
        (assert-check "encode-dot-segment helper works"
            (
                ($to_name.exit_code == 0)
                and (
                    ($to_name.stdout | lines | last | str trim) == "dot-config"
                )
            )
            $to_name.stdout)
        (assert-check "decode-dot-segment helper works"
            (
                ($from_name.exit_code == 0)
                and (($from_name.stdout | lines | last | str trim) == ".config")
            )
            $from_name.stdout)
        (assert-check "build-backup-file-path omits timestamp"
            (
                ($backup_out.exit_code == 0)
                and (
                    $backup_line
                    == "/tmp/backups/pkg/_root_/tmp/target/.vimrc"
                )
            )
            $backup_line)
    ]
}

def main [] {
    let now = (date now | format date "%Y%m%d_%H%M%S")
    let test_base = (
        $env.TMPDIR? | default "/tmp" | path join $"min-stow-test-($now)"
    )
    let source_dir = ($test_base | path join "source")
    let target_dir = ($test_base | path join "target")
    let backup_dir = ($test_base | path join "backups")
    let stow_script = (
        $env.FILE_PWD | path join ".." "min-stow.nu" | path expand
    )

    mkdir $test_base
    mkdir $source_dir
    mkdir $target_dir
    mkdir $backup_dir
    mkdir ($test_base | path join ".linux-config-logs")
    load-env { HOME: $test_base }

    mut checks = []
    log+ $"Test directory: ($test_base)"

    $checks ++= (test_add $test_base $source_dir $target_dir $stow_script)
    $checks ++= (test_apply $test_base $source_dir $backup_dir $stow_script)
    $checks ++= (test_restore $test_base $source_dir $backup_dir $stow_script)
    $checks ++= (test_helper_exports $stow_script)

    let failed = ($checks | where { |item| not $item.passed })
    print ""
    let total = ($checks | length)
    let n_failed = ($failed | length)
    print $"Summary: ($total - $n_failed) passed, ($n_failed) failed"
    do -i { ^rm -rf $test_base }
    if (not ($failed | is-empty)) { exit 1 }
}

main
