#!/usr/bin/env bash
set -euo pipefail
VM_NAME="${1:?Usage: $0 <vm-name> <windows-iso-path> [disk-size-in-gb]}"
ISO_PATH="${2:?Usage: $0 <vm-name> <windows-iso-path> [disk-size-in-gb]}"
DISK_GB="${3:-100}"
DISK_PATH="/var/lib/libvirt/images/${VM_NAME}.qcow2"
RAM_MB=32768
VCPUS=16
if [ -f "$DISK_PATH" ]; then
  echo "Error: Disk already exists at $DISK_PATH" >&2
  exit 1
fi
qemu-img create -f qcow2 "$DISK_PATH" "${DISK_GB}G"
virt-install \
  --connect qemu:///system \
  --name "$VM_NAME" \
  --ram "$RAM_MB" \
  --vcpus "$VCPUS" \
  --cpu host-passthrough,clearxml=yes \
  --machine pc-q35-11.0 \
  --boot uefi,loader_secure=yes \
  --firmware efi \
  --os-variant win11 \
  --disk path="$DISK_PATH",format=qcow2,bus=virtio,cache=none,discard=unmap \
  --disk path="$ISO_PATH",device=cdrom,bus=sata \
  --network type=direct,source=enp4s0,mode=bridge,model=virtio \
  --controller type=usb,model=qemu-xhci \
  --controller type=sata \
  --controller type=virtio-serial \
  --channel spicevmc \
  --channel qemu-vdagent,clipboard=yes \
  --graphics spice,gl.enable=no,listen=none \
  --soundhw ich9 \
  --tpm backend.type=emulator,backend.version=2.0,model=tpm-crb \
  --video none \
  --input type=keyboard,bus=ps2 \
  --input type=mouse,bus=ps2 \
  --clock offset=localtime \
  --features kvm_hidden=yes,smm=on \
  --hyperv relaxed=on,vapic=on,spinlocks=on,spinlock_retries=8191,vpindex=on,runtime=on,synic=on,stimer=on \
  --hyperv frequencies=on,tlbflush=on,ipi=on,avic=on \
  --pm suspend_to_mem=off,suspend_to_disk=off \
  --watchdog model=itco,action=reset \
  --noautoconsole

echo "VM created."
echo "  Disk: $DISK_PATH"
echo "  RAM: ${RAM_MB}M"
echo "  vCPUs: $VCPUS"
