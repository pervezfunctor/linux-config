#! /usr/bin/env nu

use lib.nu *

def find-ovmf-code [] {
  let candidates = [
    "/usr/share/edk2/x64/OVMF_CODE.4m.fd"
    "/usr/share/OVMF/OVMF_CODE.fd"
    "/usr/share/edk2-ovmf/x64/OVMF_CODE.fd"
  ]
  $candidates | where {|p| $p | path exists } | first
}

def find-ovmf-vars [] {
  let candidates = [
    "/usr/share/edk2/x64/OVMF_VARS.4m.fd"
    "/usr/share/OVMF/OVMF_VARS.fd"
    "/usr/share/edk2-ovmf/x64/OVMF_VARS.fd"
  ]
  $candidates | where {|p| $p | path exists } | first
}

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

  if not ($loader | is-empty) and not ($nvram | is-empty) {
    return { loader: $loader, nvram: $nvram }
  }

  let ovmf_code = (find-ovmf-code)
  let ovmf_vars = (find-ovmf-vars)

  let vars_dir = $"($env.HOME)/.config/qemu/nvram"
  mkdir $vars_dir
  let vars_file = $"($vars_dir)/($name)_VARS.fd"
  if not ($vars_file | path exists) {
    cp $ovmf_vars $vars_file
  }

  { loader: $ovmf_code, nvram: $vars_file }
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

  if ($xml | str contains "<loader") or ($xml | str contains 'firmware="efi"') {
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

def "main help" [] {
  print "vmm.nu - Start a QEMU/KVM VM with GPU acceleration via virtio"
  print ""
  print "Usage:"
  print "  nu vmm.nu [vm] [--firmware <auto|bios|uefi>]"
  print "  nu vmm.nu help"
  print ""
  print "Arguments:"
  print "  vm                   Name of the VM (as registered in virsh, omit for fzf picker)"
  print ""
  print "Flags:"
  print "  -f, --firmware       Firmware mode: auto|bios|uefi (default: auto)"
  print ""
  print "Examples:"
  print "  nu vmm.nu              # pick a VM via fzf"
  print "  nu vmm.nu my-vm"
  print "  nu vmm.nu my-vm --firmware uefi"
  print "  nu vmm.nu my-vm -f bios"
}

def main [
  vm: string = ""

  --firmware(-f): string = "auto" # auto|bios|uefi
] {
  let vm = (
    if ($vm | is-empty) {
      let vms = (virsh list --name --all | lines | where ($it | is-not-empty))
      if ($vms | is-empty) {
        error make { msg: "No VMs found" }
      }
      let selected = ($vms | str join (char newline) | fzf --prompt="Select VM> ")
      if ($selected | is-empty) {
        return
      }
      $selected
    } else {
      $vm
    }
  )

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

  let all_vms = (virsh list --name --all | lines | where ($it | is-not-empty) | sort)
  let vm_idx = (
    $all_vms
    | enumerate
    | where item == $vm
    | first
    | get index
  )
  let ssh_port = 2222 + $vm_idx

  mut args = [
    "-enable-kvm"
    "-M" "q35"
    "-cpu" "host"
    "-smp" ($cpus | into string)
    "-m" $"($memory_mib)M"

    "-netdev" $"user,id=net0,hostfwd=tcp::($ssh_port)-:22"
    "-device" "virtio-net-pci,netdev=net0"

    "-device" "virtio-sound-pci,audiodev=audio0"
    "-audiodev" "pipewire,id=audio0"

    "-device" "virtio-vga-gl,hostmem=4G,blob=true,venus=true"
    "-display" "gtk,gl=on,grab-on-hover=on"

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
  log+ $"SSH: ssh -p ($ssh_port) user@localhost"

  let final_args = $args
  with-env { GDK_BACKEND: "wayland" } {
    ^setsid --fork qemu-system-x86_64 ...$final_args out> /dev/null
  }
}
