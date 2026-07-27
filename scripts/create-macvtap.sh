#!/bin/bash
set -euo pipefail

SCRIPT_NAME=$(basename "$0")

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME <vm-name>

Creates a macvtap (direct) interface on the VM, bridged to the host's
default-route physical interface, so the VM gets an IP from the LAN router.

Idempotent: safe to run multiple times.
EOF
    exit 1
}

[[ $# -ne 1 ]] && usage
VM_NAME="$1"
LIBVIRT_URI="${LIBVIRT_DEFAULT_URI:-qemu:///system}"

# --- Validate VM exists ---
if ! virsh -c "$LIBVIRT_URI" dominfo "$VM_NAME" &>/dev/null; then
    echo "Error: VM '$VM_NAME' not found" >&2
    exit 1
fi

# --- Detect physical interface with default route ---
PHYS_IFACE=$(ip -4 route show default | awk '{print $5}' | head -1)
if [[ -z "$PHYS_IFACE" ]]; then
    echo "Error: no physical interface with a default route found" >&2
    exit 1
fi

# --- Check if macvtap on this physical interface already exists ---
if virsh -c "$LIBVIRT_URI" domiflist "$VM_NAME" | awk 'NR>2' | grep -qE "direct\s+$PHYS_IFACE"; then
    echo "Macvtap already exists on '$VM_NAME' via '$PHYS_IFACE' -- nothing to do"
    exit 0
fi

# --- Determine live flag based on VM state ---
VM_STATE=$(virsh -c "$LIBVIRT_URI" domstate "$VM_NAME")
LIVE_FLAG=""
[[ "$VM_STATE" == "running" ]] && LIVE_FLAG="--live"

# --- Attach macvtap ---
virsh -c "$LIBVIRT_URI" attach-interface \
    "$VM_NAME" \
    direct \
    --source "$PHYS_IFACE" \
    --model virtio \
    --config \
    $LIVE_FLAG

echo "Macvtap on '$PHYS_IFACE' attached to '$VM_NAME'"
