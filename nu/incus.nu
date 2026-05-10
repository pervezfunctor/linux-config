#!/usr/bin/env nu

use ./lib.nu *

def main [] {
  bootstrap
  main help
}

def "main list" [] {
  incus list
}

def "main list images" [] {
  incus image list images: | find "/cloud"
}

def "main search" [query: string] {
  incus image list images: | find $query | find "/cloud"
}

def "main help" [] {
  print $"Usage: incus.nu <command>
Commands:
  post-setup      Steps after installing incus and reboot
  list            List running instances
  list images     List available cloud images

  ssh <name>      SSH into a VM instance
  destroy <name>  Stop and delete a VM instance
  search <query>  Search cloud images by keyword

  debian       Create a Debian VM with cloud-init
  ubuntu       Create an Ubuntu VM with cloud-init
  fedora       Create a Fedora VM with cloud-init
  tumbleweed   Create an openSUSE Tumbleweed VM with cloud-init
  arch         Create an Arch Linux VM with cloud-init
"
}

def launch-vm [
  --image: string
  --name: string
  --ssh_key: string = ""
  --ssh_service: string = "sshd"
  --ssh_package: string = "openssh-server"
  --secureboot = true
] {
  let pubkey = get-pubkey $ssh_key
  let cloud_init = $"#cloud-config
users:
  - name: pervez
    ssh_authorized_keys:
      - ($pubkey)
    shell: /bin/bash
    sudo: ALL=\(ALL\) NOPASSWD:ALL
    lock_passwd: false
package_update: true
packages:
  - qemu-guest-agent
  - ($ssh_package)
  - wget
  - curl
runcmd:
  - systemctl enable --now ($ssh_service)
"

  incus launch $image $name --vm $"--config=cloud-init.user-data=($cloud_init)" ...(if not $secureboot { ["--config" "security.secureboot=false"] } else { [] })

  print $"\n(ansi green)> VM '($name)' created. Wait a few seconds for cloud-init to finish.(ansi reset)"
  print $"Use: incus exec ($name) -- bash -c 'cloud-init status --wait'"
}

def "main debian" [name: string = "debian", ssh_key: string = ""] {
  (launch-vm
    --image "images:debian/13/cloud"
    --name $name
    --ssh_key $ssh_key
    --ssh_service "ssh")
}

def "main ubuntu" [name: string = "ubuntu", ssh_key: string = ""] {
  (launch-vm
    --image "images:ubuntu/26.04/cloud"
    --name $name
    --ssh_key $ssh_key
    --ssh_service "ssh")
}

def "main fedora" [name: string = "fedora", ssh_key: string = ""] {
  (launch-vm
    --image "images:fedora/43/cloud"
    --name $name
    --ssh_key $ssh_key)
}

def "main tumbleweed" [name: string = "tumbleweed", ssh_key: string = ""] {
  (launch-vm
    --image "images:opensuse/tumbleweed/cloud"
    --name $name
    --ssh_key $ssh_key)
}

def "main arch" [name: string = "arch", ssh_key: string = ""] {
  (launch-vm
    --image "images:archlinux/cloud"
    --name $name
    --ssh_key $ssh_key
    --ssh_package "openssh"
    --secureboot false)
}

def "main ssh" [name: string] {
  let ip = incus list $name -c 4 --format csv
    | lines
    | parse "{ip} ({iface})"
    | where iface =~ '^e(n|th)'
    | get 0.ip
  ssh -o StrictHostKeyChecking=no pervez@($ip)
}

def "main destroy" [name: string] {
  ignore-error {|| incus stop $name }
  ignore-error {|| incus delete $name }
}

def "main post-setup" [] {
  sudo systemctl enable --now incus.socket
  incus admin init --minimal
  sudo firewall-cmd --zone=trusted --change-interface=incusbr0 --permanent
  sudo firewall-cmd --reload
}
