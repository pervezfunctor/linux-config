#!/usr/bin/env bash
set -euo pipefail
VM_NAME="${1:?Usage: $0 <vm-name> <linux-iso-path> [disk-size-in-gb]}"
ISO_PATH="${2:?Usage: $0 <vm-name> <linux-iso-path> [disk-size-in-gb]}"
DISK_GB="${3:-50}"
DISK_PATH="/home/pervez/.local/share/libvirt/images/${VM_NAME}.qcow2"
RAM_MB=16384
VCPUS=6
if [ -f "$DISK_PATH" ]; then
  echo "Error: Disk already exists at $DISK_PATH" >&2
  exit 1
fi
qemu-img create -f qcow2 "$DISK_PATH" "${DISK_GB}G"
virt-install \
  --connect qemu:///session \
  --name "$VM_NAME" \
  --ram "$RAM_MB" \
  --vcpus "$VCPUS" \
  --machine pc-q35-11.0 \
  --boot uefi,loader_secure=yes \
  --firmware efi \
  --os-variant detect=on,require=off \
  --disk path="$DISK_PATH",format=qcow2,bus=virtio,cache=none,discard=unmap \
  --disk path="$ISO_PATH",device=cdrom,bus=ide \
  --network type=user,model=virtio \
  --controller type=usb,model=qemu-xhci \
  --controller type=virtio-serial \
  --channel spicevmc \
  --channel qemu-vdagent \
  --graphics spice,gl.enable=yes,listen=none \
  --soundhw ich9 \
  --video virtio,accel3d=yes \
  --input type=tablet,bus=usb \
  --input type=keyboard,bus=usb \
  --redirdev usb \
  --redirdev usb \
  --rng /dev/urandom,model=virtio \
  --clock offset=utc \
  --watchdog model=itco,action=reset \
  --noautoconsole

echo "VM created."
echo "  Disk: $DISK_PATH"
echo "  RAM: ${RAM_MB}M"
echo "  vCPUs: $VCPUS"
