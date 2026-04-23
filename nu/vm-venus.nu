#! /usr/bin/env nu

def main [image: string] {
  let vars_file = $"/home/pervez/.config/libvirt/qemu/nvram/($image)_VARS.fd"
  let disk_file = $"/home/pervez/.local/share/libvirt/images/($image).qcow2"

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
      "-drive" "if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd"
      "-drive" $"if=pflash,format=raw,file=($vars_file)"
      "-drive" $"file=($disk_file)"
    ]

    qemu-system-x86_64 ...$args
  }
}
