#! /usr/bin/env nu

def main [image: string] {
  def main [image: string] {
    let vars_file = $"/var/lib/libvirt/qemu/nvram/($image)_VARS.fd"
    let disk_file = $"/var/lib/libvirt/images/($image).qcow2"

    let args = [
      -enable-kvm
      -M q35
      -smp 8
      -m 32G
      -cpu host
      -net nic,model=virtio
      -net user,hostfwd=tcp::2222-:22
      -device virtio-sound-pci,audiodev=my_audiodev
      -audiodev pipewire,id=my_audiodev
      -device virtio-vga-gl,hostmem=4G,blob=true,venus=true
      -vga none
      -display sdl,gl=on
      -usb
      -device usb-tablet
      -object memory-backend-memfd,id=mem1,size=32G
      -machine memory-backend=mem1
      -drive "if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.secboot.4m.fd"
      -drive $"if=pflash,format=raw,file=($vars_file)"
      -drive $"file=($disk_file)"
    ]

    do {
      ^qemu-system-x86_64 ...$args
    }
  }
}
# -display gtk,gl=on,show-cursor=on
# -display egl-headless,gl=off
