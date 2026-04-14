#!/usr/bin/env nu

use ./lib.nu *

def resolve-runtime-paths [
  target: string = "",
  source_dir: string = "",
  --backup-dir: string = "",
] {
  {
    target: ($target | or-else $env.HOME | path expand)
    source: (
        $source_dir
        | or-else ($env.HOME | path join ".local" "share" "linux-config")
        | path expand
    )
    backup: (
        $backup_dir
        | or-else ($env.HOME | path join ".stow-backups")
        | path expand
    )
  }
}

def path-relative-to-target [path: string, target: string] {
  try {
    $path | path relative-to $target
  } catch {
    raise-error $"Path ($path) is outside target ($target)" $path
  }
}

def package-source-root [source_dir: string, package: string] {
  $source_dir | path join $package
}

def build-staged-file-path [
  package: string,
  source_dir: string,
  abs_path: string,
  abs_target: string,
] {
  package-source-root $source_dir $package
  | path join ...(
    path-relative-to-target $abs_path $abs_target
    | path split
    | each { |p| encode-dot-segment $p }
    )
}

def build-backup-file-path [
  backup_dir: string,
  package: string,
  abs_target: string,
  target_path: string,
] {
  let scope = (
    $abs_target
    | path split
    | each { |part|
        if $part in ["", "/"] { "_root_" } else { encode-dot-segment $part }
    }
  )
  $backup_dir
  | path join $package
  | path join ...$scope
  | path join (path-relative-to-target $target_path $abs_target)
}

def backup-replaced-target [
  backup_dir: string,
  package: string,
  abs_target: string,
  target_path: string,
] {
  let kind = (detect-path-kind $target_path)
  if $kind == "dir" {
    raise-error $"Destination is a directory: ($target_path)" $target_path
  }
  if $kind == "none" { return }

  if $kind == "symlink" {
    ^rm -f $target_path
    return
  }

  let dst = (
    build-backup-file-path $backup_dir $package $abs_target $target_path
  )
  ensure-parent-dir $dst
  if ($dst | path exists) {
    if (has-cmd "trash") {
      ^trash $dst
    } else {
      ^rm -rf $dst
    }
  }
  ^cp -p $target_path $dst
  ^rm -f $target_path
}

def list-package-target-mappings [pkg_root: string, abs_target: string] {
  glob $"($pkg_root)/**/*"
  | where { |item| ($item | path type) != "dir" and $item != $pkg_root }
  | each { |item|
      let rel = ($item | path relative-to $pkg_root)
      {
          stow: ($item | path expand)
          target: (
              $abs_target
              | path join ...(
                  $rel | path split | each { |p| decode-dot-segment $p }
              )
          )
      }
  }
}

def link-package-targets [
  target_mappings: list<record<stow: string, target: string>>
] {
  for item in $target_mappings {
    ensure-parent-dir $item.target
    ^ln -sf $item.stow $item.target
  }
}

def restore-target-from-backup [
  backup_dir: string,
  package: string,
  abs_target: string,
  target_path: string,
] {
  let src = (
    build-backup-file-path $backup_dir $package $abs_target $target_path
  )
  if not ($src | path exists) { return }
  let kind = (detect-path-kind $target_path)
  if $kind == "dir" {
    raise-error $"Destination is a directory: ($target_path)" $target_path
  }
  if $kind in ["file", "symlink"] { ^rm -f $target_path }
  ensure-parent-dir $target_path
  ^cp -p $src $target_path
}

export def "main add" [
  package: string,
  path: string,
  --target: string,
  --source-dir: string,
] {
  if ($package | is-empty) {
    raise-error "package is required" $package
  }
  check-file $path
  let dirs = (resolve-runtime-paths $target $source_dir)
  let abs_path = ($path | path expand)
  let dst = (
    build-staged-file-path $package $dirs.source $abs_path $dirs.target
  )
  ensure-parent-dir $dst
  ^cp -p -f $path $dst
  ^rm -f $abs_path
  ^ln -sf $dst $abs_path
}

export def "main apply" [
  package: string,
  --target: string,
  --source-dir: string,
  --backup-dir: string,
] {
  let dirs = (
    resolve-runtime-paths $target $source_dir --backup-dir $backup_dir
  )
  let pkg_root = (package-source-root $dirs.source $package)
  if not ($pkg_root | path exists) {
    raise-error $"Package does not exist: ($package)" $pkg_root
  }
  let items = (
    list-package-target-mappings ($pkg_root | path expand) $dirs.target
  )
  for item in $items {
    backup-replaced-target $dirs.backup $package $dirs.target $item.target
  }
  link-package-targets $items
}

export def "main restore" [
  package: string,
  --target: string,
  --source-dir: string,
  --backup-dir: string,
] {
  let dirs = (
    resolve-runtime-paths $target $source_dir --backup-dir $backup_dir
  )
  let pkg_root = (package-source-root $dirs.source $package)
  if not ($pkg_root | path exists) {
    raise-error $"Package does not exist: ($package)" $pkg_root
  }
  let items = (
    list-package-target-mappings ($pkg_root | path expand) $dirs.target
  )
  for item in $items {
    (
      restore-target-from-backup
      $dirs.backup
      $package
      $dirs.target
      $item.target
    )
  }
}

export def "main help" [] {
  print "min-stow

USAGE:
  stow add <package> <path> [--target <dir>] [--source-dir <dir>]
  stow apply <package> [--target <dir>] [--source-dir <dir>]
    [--backup-dir <dir>]
  stow restore <package> [--target <dir>] [--source-dir <dir>]
    [--backup-dir <dir>]"
}

def main [] {
    main help
}
