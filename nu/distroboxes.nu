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

def list-tmuxp-boxes [] {
  let boxes = (do -i { ^distrobox list } | complete)
  if $boxes.exit_code != 0 {
    return []
  }
  $boxes.stdout | lines | skip 1 | parse "{id}|{name}|{status}|{image}" | get name | each { str trim } | where { $it =~ "-tmuxp$" }
}

def box-exists [name: string] {
  let result = (do -i { ^distrobox list } | complete)
  if $result.exit_code != 0 {
    return false
  }

  let boxes = ($result.stdout | lines | skip 1 | parse "{id}|{name}|{status}|{image}" | get name | str trim)
  $name in $boxes
}

def create-box [
  name: string
  image: string
] {
  log info $"Checking distrobox '($name)'..."

  if (box-exists $name) {
    log info $"Distrobox '($name)' already exists, skipping..."
    return true
  }

  let box_home = ($nu.home-dir | path join ".boxes" $name)

  if not ($box_home | path exists) {
    log info $"Creating home directory at ($box_home)..."
    mkdir $box_home
  }

  log info $"Creating distrobox '($name)' with image '($image)'..."
  log info $"Home directory: ($box_home)"

  let result = (do -i { ^distrobox create --name $name --image $image --home $box_home --yes } | complete)

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
    {name: "ubuntu-tmuxp", image: "ubuntu:latest"},
    {name: "debian-tmuxp", image: "debian:latest"},
    {name: "fedora-tmuxp", image: "fedora:latest"},
    {name: "arch-tmuxp", image: "archlinux:latest"},
    {name: "tumbleweed-tmuxp", image: "opensuse/tumbleweed:latest"},
    {name: "alpine-tmuxp", image: "alpine:latest"},
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
  --yes (-y)  # Skip confirmation prompts
] {
  if not (box-exists $name) {
    log warning $"Distrobox '($name)' does not exist"
    return false
  }

  log info $"Removing distrobox '($name)'..."

  let result = (do -i { ^distrobox rm $name --yes } | complete)

  if $result.exit_code == 0 {
    log info $"Successfully removed distrobox '($name)'"

    let box_home = ($nu.home-dir | path join ".boxes" $name)
    if ($box_home | path exists) {
      if $yes {
        log info $"Removing home directory at ($box_home)..."
        rm -rf $box_home
        log info "Home directory removed"
      } else {
        log warning $"Found home directory at ($box_home)"
        let response = (input "Remove home directory? (y/N): ")

        if $response =~ "(?i)^y(es)?$" {
          log info $"Removing home directory at ($box_home)..."
          rm -rf $box_home
          log info "Home directory removed"
        } else {
          log info "Home directory preserved"
        }
      }
    }

    return true
  } else {
    log error $"Failed to remove distrobox '($name)'"
    return false
  }
}

def "main remove-all" [
  --yes (-y)  # Skip confirmation prompt
] {
  check-distrobox

  if not $yes {
    log warning "This will remove all distroboxes created by this script!"
    let response = (input "Are you sure? (y/N): ")

    if $response !~ "(?i)^y(es)?$" {
      log info "Operation cancelled"
      return
    }
  }

  let box_names = (list-tmuxp-boxes)

  if ($box_names | is-empty) {
    log info "No tmuxp distroboxes found"
    return
  }

  log info "Removing all tmuxp distroboxes..."

  let failed = $box_names | each { |box|
    if not (if $yes { remove-box $box --yes } else { remove-box $box }) {
      $box
    }
  } | compact

  if ($failed | is-empty) {
    log info "All tmuxp distroboxes removed successfully"
  } else {
    log error $"Failed to remove: ($failed | str join ', ')"
    error make {
      msg: "Some distroboxes failed to remove"
    }
  }
}

def start-box [
  name: string
] {
  log info $"Starting distrobox '($name)'..."

  let result = (do -i { ^podman start $name } | complete)

  if $result.exit_code == 0 {
    log info $"Successfully started distrobox '($name)'"
    return true
  } else {
    log error $"Failed to start distrobox '($name)'"
    return false
  }
}

def "main start-all" [] {
  check-distrobox

  let box_names = (list-tmuxp-boxes)

  if ($box_names | is-empty) {
    log info "No tmuxp distroboxes found"
    return
  }

  log info "Starting all tmuxp distroboxes..."

  let failed = $box_names | each { |box|
    if not (start-box $box) {
      $box
    }
  } | compact

  if ($failed | is-empty) {
    log info "All tmuxp distroboxes started successfully"
  } else {
    log error $"Failed to start: ($failed | str join ', ')"
    error make {
      msg: "Some distroboxes failed to start"
    }
  }
}

def stop-box [
  name: string
] {
  log info $"Stopping distrobox '($name)'..."

  let result = (do -i { ^podman stop $name } | complete)

  if $result.exit_code == 0 {
    log info $"Successfully stopped distrobox '($name)'"
    return true
  } else {
    log error $"Failed to stop distrobox '($name)'"
    return false
  }
}

def "main stop-all" [] {
  check-distrobox

  let box_names = (list-tmuxp-boxes)

  if ($box_names | is-empty) {
    log info "No tmuxp distroboxes found"
    return
  }

  log info "Stopping all tmuxp distroboxes..."

  let failed = $box_names | each { |box|
    if not (stop-box $box) {
      $box
    }
  } | compact

  if ($failed | is-empty) {
    log info "All tmuxp distroboxes stopped successfully"
  } else {
    log error $"Failed to stop: ($failed | str join ', ')"
    error make {
      msg: "Some distroboxes failed to stop"
    }
  }
}

def "main restart-all" [] {
  check-distrobox

  log info "Restarting all distroboxes..."
  print ""

  main stop-all
  print ""

  main start-all
}

def "main enter-all" [] {
  check-distrobox

  let box_names = (list-tmuxp-boxes)

  if ($box_names | is-empty) {
    log info "No tmuxp distroboxes found"
    return
  }

  log info $"Found ($box_names | length) tmuxp distrobox(es)"
  print ""

  for box in $box_names {
    log info $"Entering distrobox '($box)'..."
    ^distrobox enter --name $box --clean-path -- echo ""
    print ""
  }

  log info "Finished entering all distroboxes"
}

def "main exec-all" [
  ...cmd: string  # Command and arguments to execute in all distroboxes
] {
  check-distrobox

  if ($cmd | is-empty) {
    log error "No command specified"
    print "Usage: distroboxes.nu exec-all <command> [args...]"
    error make {
      msg: "No command specified"
    }
  }

  let box_names = (list-tmuxp-boxes)

  if ($box_names | is-empty) {
    log info "No tmuxp distroboxes found"
    return
  }

  let command_str = ($cmd | str join " ")
  log info $"Executing '($command_str)' in all tmuxp distroboxes..."
  print ""

  let results = $box_names | each { |box|
    log info $"[($box)] Executing command..."
    let result = (do -i { ^distrobox enter $box -- ...$cmd } | complete)

    if $result.exit_code == 0 {
      log info $"[($box)] Command completed successfully"
      if ($result.stdout | is-not-empty) {
        print $result.stdout
      }
      null
    } else {
      log error $"[($box)] Command failed with exit code ($result.exit_code)"
      if ($result.stderr | is-not-empty) {
        print $result.stderr
      }
      $box
    }
  } | compact

  print ""
  if ($results | is-empty) {
    log info "Command executed successfully in all tmuxp distroboxes"
  } else {
    log error $"Command failed in the following distroboxes: ($results | str join ', ')"
    error make {
      msg: "Command failed in some distroboxes"
    }
  }
}

def "main enter" [
  name: string      # Name of the distrobox to enter
  ...cmd: string    # Optional command and arguments to execute (default: shell)
] {
  check-distrobox

  if not (box-exists $name) {
    log error $"Distrobox '($name)' does not exist"
    error make {
      msg: $"Distrobox '($name)' does not exist"
    }
  }

  if ($cmd | is-empty) {
    log info $"Entering distrobox '($name)'..."
    ^distrobox enter --name $name --clean-path
  } else {
    let command_str = ($cmd | str join " ")
    log info $"Entering distrobox '($name)' and executing: ($command_str)"
    ^distrobox enter --name $name --clean-path -e ...$cmd
  }
}

def "main help" [] {
  print "Usage: distroboxes.nu [COMMAND]"
  print ""
  print "Commands:"
  print "  create-all     Create all distroboxes (default)"
  print "  list           List existing distroboxes"
  print "  remove-all     Remove all tmuxp distroboxes (interactive)"
  print "  start-all      Start all tmuxp distroboxes"
  print "  stop-all       Stop all tmuxp distroboxes"
  print "  restart-all    Restart all tmuxp distroboxes"
  print "  exec-all       Execute a command in all tmuxp distroboxes"
  print "  enter          Enter a specific distrobox (with --clean-path)"
  print "  enter-all     Enter all tmuxp distroboxes sequentially"
  print "  help           Show this help message"
  print ""
  print "Distroboxes created:"
  print "  - ubuntu-tmuxp (latest)"
  print "  - debian-tmuxp (latest)"
  print "  - fedora-tmuxp (latest)"
  print "  - arch-tmuxp (latest)"
  print "  - tumbleweed-tmuxp (latest)"
  print "  - alpine-tmuxp (latest)"
  print ""
  print "Home directories:"
  print "  Each distrobox uses a custom home directory in ~/.boxes/<name>"
  print "  This keeps container files separate from your host home"
  print ""
  print "Note:"
  print "  All commands (except enter, list) operate only on boxes ending with -tmuxp"
  print ""
  print "Examples:"
  print "  distroboxes.nu create-all          # Create all distroboxes"
  print "  distroboxes.nu list                # List existing boxes"
  print "  distroboxes.nu remove-all          # Remove all tmuxp boxes"
  print "  distroboxes.nu start-all           # Start all tmuxp boxes"
  print "  distroboxes.nu stop-all            # Stop all tmuxp boxes"
  print "  distroboxes.nu restart-all         # Restart all tmuxp boxes"
  print "  distroboxes.nu exec-all uname -a   # Run command in all tmuxp boxes"
  print "  distroboxes.nu enter debian-tmuxp  # Enter debian-tmuxp shell"
  print "  distroboxes.nu enter alpine-tmuxp uname -a # Run command in alpine-tmuxp"
  print "  distroboxes.nu enter-all           # Enter all tmuxp boxes sequentially"
}

def main [] {
  main create-all
}
