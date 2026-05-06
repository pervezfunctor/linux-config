#!/usr/bin/env nu

use ./lib.nu *
use std/util "path add"


const DOTFILES_URL = "https://github.com/pervezfunctor/linux-config.git"
const DOT_DIR = ($nu.home-dir | path join ".linux-config")

def dotfiles-validate [] {
  ^git -C $DOT_DIR rev-parse --is-inside-work-tree | ignore
  let remote_url = (
    ^git -C $DOT_DIR remote get-url origin | str trim
  )
  if ($remote_url | is-empty) {
    error make {
      msg: "Remote URL is empty. Is 'origin' configured?"
    }
  }
  if $remote_url != $DOTFILES_URL {
    error make {
      msg: $"Unexpected remote: expected '($DOTFILES_URL)', got '($remote_url)'"
    }
  }

  ^git -C $DOT_DIR status --porcelain=v1
}

def abort-rebase-if-needed [] {
  let rebase_merge = ($DOT_DIR | path join ".git" "rebase-merge")
  let rebase_apply = ($DOT_DIR | path join ".git" "rebase-apply")
  if ($rebase_merge | path exists) or ($rebase_apply | path exists) {
    warn+ "Aborting rebase"
    ignore-error {|| ^git -C $DOT_DIR rebase --abort }
  }
}

def dotfiles-pull-clean [] {
  log+ "Pulling latest changes (clean repo)"
  let result = (
    do { ^git -C $DOT_DIR pull --rebase --stat } | complete
  )
  if $result.exit_code != 0 {
    abort-rebase-if-needed
    error make {
      msg: "git pull --rebase failed on clean repo"
    }
  }
  log+ "Dotfiles updated"
}

def dotfiles-pull-dirty [] {
  log+ "Stashing local changes before pull"
  let stash_label = (
    $"setup-autostash-(date now | format date '%s')"
  )
  ^git -C $DOT_DIR stash push --include-untracked -m $stash_label

  let pull = (
    do { ^git -C $DOT_DIR pull --rebase --stat } | complete
  )
  if $pull.exit_code != 0 {
    abort-rebase-if-needed
  }

  log+ "Restoring local changes from stash"
  let pop = (
    do { ^git -C $DOT_DIR stash pop } | complete
  )
  if $pop.exit_code != 0 {
    error make {
      msg: "Stash pop failed — working tree may have conflicts"
    }
  }

  if $pull.exit_code != 0 {
    error make {
      msg: "git pull --rebase failed; local changes restored"
    }
  }
  log+ "Dotfiles updated"
}

def "main dotfiles clone" [] {
  let git_dir = ($DOT_DIR | path join ".git")
  if not ($git_dir | path exists) {
    log+ "Cloning dotfiles"
    ^git clone $DOTFILES_URL $DOT_DIR
    return
  }

  let status = (dotfiles-validate)
  if ($status | is-empty) {
    dotfiles-pull-clean
  } else {
    dotfiles-pull-dirty
  }
}

def "main dotfiles" [] {
  main dotfiles clone

  main nushell config
  main fish config
}
