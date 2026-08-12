#! /usr/bin/env nu

use lib.nu *

def get-uefi-paths [name: string] {
  let xml = (virsh dumpxml $name)

  let loader = (
    $xml
    | lines
    | where ($it | str contains "<loader")
    | parse --regex '.*>(?<path>[^<]+)</loader>'
    | get path
    | first
  )

  let nvram = (
    $xml
    | lines
    | where ($it | str contains "<nvram")
    | parse --regex '.*>(?<path>[^<]+)</nvram>'
    | get path
    | first
  )

  {
    loader: $loader
    nvram: $nvram
  }
}

def get-vm-disk [name: string] {
  let path = (
    virsh domblklist $name
    | lines
    | skip 2
    | str trim
    | split column -r '\s+' target source
    | where source != "-"
    | get source
    | first
  )

  if ($path | is-empty) {
    error make {
      msg: $"Unable to determine disk for VM '($name)'"
    }
  }

  $path
}

def get-vm-firmware [name: string] {
  let xml = (virsh dumpxml $name)

  if ($xml | str contains "<loader") {
    "uefi"
  } else {
    "bios"
  }
}

def get-vm-memory-mib [name: string] {
  (
    virsh dominfo $name
    | lines
    | where ($it | str starts-with "Max memory:")
    | first
    | parse "Max memory: {mem} KiB"
    | get mem.0
    | into int
  ) / 1024
}

def get-vm-vcpus [name: string] {
  (
    virsh dominfo $name
    | lines
    | where ($it | str starts-with "CPU(s):")
    | first
    | parse "CPU(s): {cpus}"
    | get cpus.0
    | into int
  )
}

def ensure-vars-file [vm: string vars_template: string] {
  let vars_dir = $"($env.HOME)/.config/qemu/nvram"
  mkdir $vars_dir

  let vars_file = $"($vars_dir)/($vm)_VARS.fd"

  if not ($vars_file | path exists) {
    cp $vars_template $vars_file
  }

  $vars_file
}

def main [
  vm: string

  --firmware(-f): string = "auto" # auto|bios|uefi
] {
  log+ $"Starting VM '($vm)'..."
  log+ "Make sure mesa, virglrenderer and vulkan-virtio are installed"

  let disk_file = (get-vm-disk $vm)

  let detected_fw = (get-vm-firmware $vm)

  let firmware = (
    if $firmware == "auto" {
      $detected_fw
    } else {
      $firmware
    }
  )

  let memory_mib = (get-vm-memory-mib $vm)
  let cpus = (get-vm-vcpus $vm)

  mut args = [
    "-enable-kvm"
    "-M" "q35"
    "-cpu" "host"
    "-smp" ($cpus | into string)
    "-m" $"($memory_mib)M"

    "-netdev" "user,id=net0,hostfwd=tcp::2222-:22"
    "-device" "virtio-net-pci,netdev=net0"

    "-device" "virtio-sound-pci,audiodev=audio0"
    "-audiodev" "pipewire,id=audio0"

    "-device" "virtio-vga-gl,hostmem=4G,blob=true,venus=true"
    "-display" "sdl,gl=on"

    "-usb"
    "-device" "usb-tablet"

    "-object" $"memory-backend-memfd,id=mem1,size=($memory_mib)M"
    "-machine" "memory-backend=mem1"

    "-drive" $"file=($disk_file),format=qcow2,if=none,id=drive0"
    "-device" "virtio-blk-pci,drive=drive0,bootindex=1"
  ]

  if $firmware == "uefi" {
    let uefi = (get-uefi-paths $vm)

    if ($uefi.loader | is-empty) or ($uefi.nvram | is-empty) {
      error make {
        msg: $"Unable to determine UEFI firmware paths for VM '($vm)'"
      }
    }

    $args ++= [
      "-drive" $"if=pflash,format=raw,readonly=on,file=($uefi.loader)"
      "-drive" $"if=pflash,format=raw,file=($uefi.nvram)"
    ]
  }

  log+ $"Firmware: ($firmware)"
  log+ $"Disk: ($disk_file)"

  let final_args = $args
  with-env { GDK_BACKEND: "wayland" } {
    qemu-system-x86_64 ...$final_args
  }
}
