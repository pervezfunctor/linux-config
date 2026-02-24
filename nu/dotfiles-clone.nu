#!/usr/bin/env nu

use ./lib/logs.nu *
use ./lib/lib.nu *

export-env {
    $env.DOT_DIR = ($env.DOT_DIR? | default ($env.HOME | path join ".local/share/linux-config"))
    $env.DOT_REPO = ($env.DOT_REPO? | default "https://github.com/pervezfunctor/linux-config.git")
}

def is-git-repo [path: string]: nothing -> bool {
    if not (dir-exists $path) { return false }
    let result = do -i { ^git -C $path rev-parse --is-inside-work-tree } | complete
    $result.exit_code == 0
}

def get-git-status [path: string]: nothing -> string {
    let result = do -i { ^git -C $path status --porcelain=v1 } | complete
    if $result.exit_code != 0 { return "" }
    $result.stdout | str trim
}

def git-stash-create [path: string, label: string] {
    let result = do -i { ^git -C $path stash push --include-untracked --message $label } | complete
    if $result.exit_code != 0 { return null }
    let stash_list = do -i { ^git -C $path stash list } | complete
    if $stash_list.exit_code != 0 { return null }
    let first_line = ($stash_list.stdout | lines | first)
    if ($first_line | is-empty) { return null }
    $first_line | split row ":" | first
}

def git-stash-apply [path: string, stash_ref: string]: nothing -> bool {
    let result = do -i { ^git -C $path stash apply $stash_ref } | complete
    $result.exit_code == 0
}

def git-stash-drop [path: string, stash_ref: string]: nothing -> bool {
    let result = do -i { ^git -C $path stash drop $stash_ref } | complete
    $result.exit_code == 0
}

def git-pull-rebase [path: string]: nothing -> bool {
    let result = do -i { ^git -C $path pull --rebase --stat } | complete
    $result.exit_code == 0
}

def git-rebase-abort [path: string]: nothing -> bool {
    let result = do -i { ^git -C $path rebase --abort } | complete
    $result.exit_code == 0
}

def clone-repo [repo_dir: string, repo_url: string]: nothing -> bool {
    log+ $"Cloning dotfiles to ($repo_dir)"
    let exit_code = try {
        ^git clone --depth 1 $repo_url $repo_dir
        0
    } catch {
        $env.LAST_EXIT_CODE
    }
    if $exit_code != 0 {
        error+ $"Failed to clone dotfiles (exit ($exit_code))"
        return false
    }
    true
}

def handle-clean-repo [path: string]: nothing -> bool {
    log+ "Dotfiles repo clean. Pulling latest changes"
    if (git-pull-rebase $path) {
        log+ "Dotfiles updated"
        return true
    }
    warn+ "git pull --rebase failed. Attempting to abort rebase"
    git-rebase-abort $path
    false
}

def handle-dirty-repo [path: string]: nothing -> bool {
    log+ "Dotfiles repo has local changes. Stashing before pull"

    let stash_label = $"bootstrap-autostash-(date now | format date '%s')"
    let stash_ref = (git-stash-create $path $stash_label)

    if ($stash_ref | is-empty) {
        error+ "Failed to stash local changes"
        return false
    }

    if (git-pull-rebase $path) {
        log+ "Pull succeeded. Restoring local changes"
        if (git-stash-apply $path $stash_ref) {
            git-stash-drop $path $stash_ref
            log+ "Local changes restored"
            return true
        }
        warn+ $"Failed to reapply stashed changes. Stash ($stash_ref) preserved"
        return false
    }

    warn+ "git pull --rebase failed with local changes. Restoring state"
    git-rebase-abort $path

    if (git-stash-apply $path $stash_ref) {
        git-stash-drop $path $stash_ref
        warn+ "Reapplied stashed changes after pull failure"
    } else {
        warn+ "Failed to reapply stashed changes after pull failure. Use git stash list"
    }
    false
}

def update-existing-repo [path: string]: nothing -> bool {
    if not (is-git-repo $path) {
        error+ $"($path) is not a git repository"
        return false
    }

    let status = (get-git-status $path)
    if ($status | is-empty) {
        handle-clean-repo $path
    } else {
        handle-dirty-repo $path
    }
}

export def dotfiles-clone []: nothing -> bool {
    let repo_dir = $env.DOT_DIR
    let repo_url = $env.DOT_REPO

    if not (dir-exists $repo_dir) {
        return (clone-repo $repo_dir $repo_url)
    }

    update-existing-repo $repo_dir
}

export def main [] {
    dotfiles-clone
}
