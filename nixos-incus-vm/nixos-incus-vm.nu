#!/usr/bin/env nu

use std/log

const nixos_config = path self

def main [name: string = "nixos", ssh_key: string = ""] {
  let pubkey = get-pubkey $ssh_key
  let base = ($nixos_config | path dirname)
  let flake = open --raw ($base | path join "flake.nix") | str replace "__HOSTNAME__" $name
  let config = open --raw ($base | path join "vm.nix") | str replace "__SSH_KEY__" $pubkey

  log info "Launching NixOS VM"
  incus launch images:nixos/25.11 $name --vm --config security.secureboot=false --config limits.memory=4GiB

  log info "Waiting for VM agent"
  sleep 30sec

  log info "Setting up nix-config directory"
  incus exec $name -- bash -c "source /etc/set-environment && mkdir -p /root/nix-config && cp /etc/nixos/* /root/nix-config/"

  log info "Pushing flake.nix and vm.nix"
  $flake | incus file push - $"($name)/root/nix-config/flake.nix"
  $config | incus file push - $"($name)/root/nix-config/vm.nix"

  log info "Starting nixos-rebuild via systemd-run (this may take a while)"
  incus exec $name -- bash -c $"source /etc/set-environment && cd /root/nix-config && systemd-run --unit=nixos-rebuild --no-block -- /run/current-system/sw/bin/bash -c 'source /etc/set-environment && cd /root/nix-config && nixos-rebuild switch --flake \".#($name)\"'"

  mut done = false
  while not $done {
    sleep 15sec
    let status = incus exec $name -- bash -c "source /etc/set-environment && systemctl is-active nixos-rebuild.service" | str trim
    if $status == "inactive" or $status == "failed" {
      $done = true
      if $status == "failed" {
        log error $"Rebuild failed. Check: incus exec ($name) -- journalctl -u nixos-rebuild.service"
        return
      }
    } else {
      log info "Rebuild in progress..."
    }
  }

  print $"\n(ansi green)> NixOS VM '($name)' created and configured.(ansi reset)"
  print $"Use: nixos-incus-vm.nu ssh ($name)"
}
