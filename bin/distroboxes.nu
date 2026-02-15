#!/usr/bin/env nu

use std/log

def check-distrobox [] {
  if (which distrobox | is-empty) {
    log error "distrobox is not installed"
    error make {
      msg: "distrobox is not installed"
    }
  }
}

def box-exists [name: string]: nothing -> bool {
  let result = (do -i { ^distrobox list } | complete)
  if $result.exit_code != 0 {
    return false
  }

  let boxes = ($result.stdout | lines | skip 1 | parse "{id}|{name}|{status}|{image}" | get name)
  $name in $boxes
}

def create-box [
  name: string
  image: string
]: nothing -> bool {
  log info $"Checking distrobox '($name)'..."

  if (box-exists $name) {
    log info $"Distrobox '($name)' already exists, skipping..."
    return true
  }

  log info $"Creating distrobox '($name)' with image '($image)'..."

  let result = (do -i { ^distrobox create --name $name --image $image --yes } | complete)

  if $result.exit_code == 0 {
    log info $"Successfully created distrobox '($name)'"
    return true
  } else {
    log error $"Failed to create distrobox '($name)'"
    return false
  }
}

def "main create-all" [] {
  check-distrobox

  let boxes = [
    {name: "ubuntu", image: "ubuntu:latest"},
    {name: "debian", image: "debian:latest"},
    {name: "fedora", image: "fedora:latest"},
    {name: "arch", image: "archlinux:latest"},
    {name: "tumbleweed", image: "opensuse/tumbleweed:latest"},
    {name: "alpine", image: "alpine:latest"},
  ]

  log info "Starting distrobox creation process..."
  print ""

  let failed = $boxes | each { |box|
    let success = (create-box $box.name $box.image)
    print ""
    if not $success {
      $box.name
    }
  } | compact

  if ($failed | is-empty) {
    log info "All distroboxes created successfully!"
    print ""
    log info "Available distroboxes:"
    ^distrobox list
  } else {
    log error $"Failed to create the following distroboxes: ($failed | str join ', ')"
    error make {
      msg: "Some distroboxes failed to create"
    }
  }
}

def "main list" [] {
  check-distrobox
  log info "Existing distroboxes:"
  ^distrobox list
}

def remove-box [
  name: string
]: nothing -> bool {
  if not (box-exists $name) {
    log warning $"Distrobox '($name)' does not exist"
    return false
  }

  log info $"Removing distrobox '($name)'..."

  let result = (do -i { ^distrobox rm $name --yes } | complete)

  if $result.exit_code == 0 {
    log info $"Successfully removed distrobox '($name)'"
    return true
  } else {
    log error $"Failed to remove distrobox '($name)'"
    return false
  }
}

def "main remove-all" [] {
  check-distrobox

  log warning "This will remove all distroboxes!"
  let response = (input "Are you sure? (y/N): ")

  if $response !~ "(?i)^y(es)?$" {
    log info "Operation cancelled"
    return
  }

  let boxes = (do -i { ^distrobox list | lines | skip 1 | parse "{id}|{name}|{status}|{image}" | get name } | complete)

  if $boxes.exit_code != 0 or ($boxes.stdout | is-empty) {
    log info "No distroboxes found"
    return
  }

  log info "Removing all distroboxes..."

  let box_names = ($boxes.stdout | lines | skip 1 | parse "{id}|{name}|{status}|{image}" | get name)
  let failed = $box_names | each { |box|
    if not (remove-box $box) {
      $box
    }
  } | compact

  if ($failed | is-empty) {
    log info "All distroboxes removed successfully"
  } else {
    log error $"Failed to remove: ($failed | str join ', ')"
    error make {
      msg: "Some distroboxes failed to remove"
    }
  }
}

def "main help" [] {
  print "Usage: distroboxes.nu [COMMAND]"
  print ""
  print "Commands:"
  print "  create-all     Create all distroboxes (default)"
  print "  list           List existing distroboxes"
  print "  remove-all     Remove all distroboxes (interactive)"
  print "  help           Show this help message"
  print ""
  print "Distroboxes created:"
  print "  - ubuntu (latest)"
  print "  - debian (latest)"
  print "  - fedora (latest)"
  print "  - arch (latest)"
  print "  - tumbleweed (latest)"
  print "  - alpine (latest)"
  print ""
  print "Examples:"
  print "  distroboxes.nu create  # Create all distroboxes"
  print "  distroboxes.nu list    # List existing boxes"
  print "  distroboxes.nu remove  # Remove all boxes"
}

def main [] {
  main create-all
}
