#! /usr/bin/env nu

def main [] {
  let vars_file = $"/home/pervez/.local/share/gnome-boxes/images/OVMF_VARS_4M.secboot.qcow2"
  let disk_file = $"/home/pervez/.local/share/gnome-boxes/images/archlinux"

  with-env { GDK_BACKEND: wayland} {
    let args = [
      "-enable-kvm"
      "-M" "q35"
      "-smp" "8"
      "-m" "32G"
      "-cpu" "host"
      "-net" "nic,model=virtio"
      "-net" "user,hostfwd=tcp::2222-:22"
      "-device" "virtio-sound-pci,audiodev=my_audiodev"
      "-audiodev" "pipewire,id=my_audiodev"
      "-device" "virtio-vga-gl,hostmem=4G,blob=true,venus=true"
      "-vga" "none"
      "-display" "gtk,gl=on,grab-on-hover=on"
      "-usb"
      "-device" "usb-tablet"
      "-object" "memory-backend-memfd,id=mem1,size=32G"
      "-machine" "memory-backend=mem1"
      "-drive" "if=pflash,format=qcow2,readonly=on,file=/usr/share/edk2/ovmf/OVMF_CODE_4M.secboot.qcow2"
      "-drive" $"if=pflash,format=qcow2,file=($vars_file)"
      "-drive" $"file=($disk_file)"
    ]

    qemu-system-x86_64 ...$args
  }
}
