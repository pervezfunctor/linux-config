#! /usr/bin/env nu

use std/log

export-env {
  $env.BOXES_DIR = ($nu.home-dir | path join ".boxes")
}

def ensure-name [name?: string] {
    if ($name | is-empty) { "default" } else { $name }
}

def "main create" [--image: string, container_name?: string] {
    let name = (ensure-name $container_name)
    let dir = ($env.BOXES_DIR | path join $name)

    if ($dir | path exists) {
      print $"Directory ($dir) already exists. Skipping creation."
    } else {
      mkdir $env.BOXES_DIR
      distrobox create --home $dir --name $name --image $image
    }
}

def "main enter" [container_name?: string] {
    let name = (ensure-name $container_name)
    distrobox enter $name -nw --clean-path
}

def "main fedora" [container_name = "fedora"] {
  main create --image quay.io/fedora/fedora-toolbox:44 $container_name
}

def "main arch" [container_name = "arch"] {
  main create --image quay.io/toolbx/arch-toolbox:latest $container_name
}

def "main ubuntu" [container_name = "ubuntu"] {
  main create --image quay.io/toolbx/ubuntu-toolbox:25.04 $container_name
}

def "main debian" [container_name = "debian"] {
    main create --image quay.io/toolbx-images/debian-toolbox:13 $container_name
}

def "main tumbleweed" [container_name = "tumbleweed"] {
    main create --image quay.io/toolbx-images/opensuse-toolbox:tumbleweed $container_name
}

def "delete" [container_name?: string] {
    let name = (ensure-name $container_name)

    log info "Deleted container: $name"
    distrobox rm -y $name

    log info "Trashed container directory: $dir"
    trash ($env.BOXES_DIR | path join $name)
}

def "list" [] {
    distrobox list
}

def main [] {

}
