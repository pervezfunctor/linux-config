#!/usr/bin/env bash
set -euo pipefail

ROM_DIR="/usr/share/kvm"
ROM_NAME="igd.rom"

RED=$'\033[0;31m'
GRN=$'\033[0;32m'
YLW=$'\033[1;33m'
CYN=$'\033[0;36m'
BOLD=$'\033[1m'
NC=$'\033[0m'

info()  { printf '%s[INFO]%s %s\n' "$CYN" "$NC" "$*"; }
ok()    { printf '%s[ OK ]%s %s\n' "$GRN" "$NC" "$*"; }
warn()  { printf '%s[WARN]%s %s\n' "$YLW" "$NC" "$*"; }
die()   { printf '%s[FAIL]%s %s\n' "$RED" "$NC" "$*" >&2; exit 1; }

usage() {
    cat <<EOF
${BOLD}Intel iGPU Passthrough VM Configurator${NC}
Configures a Proxmox VM for Intel iGPU GVT-d passthrough (Legacy Mode).
Based on: https://github.com/LongQT-sea/intel-igpu-passthru

${BOLD}Usage:${NC}
  $0 <VMID> [OPTIONS]

${BOLD}Options:${NC}
  --pci <addr>        iGPU PCI address (default: auto-detect, e.g. 0000:00:02.0)
  --rom <path>        ROM file path (default: $ROM_DIR/$ROM_NAME)
  --yes               Skip confirmation prompt
  --start             Start the VM after configuration
  -h, --help          Show this help

${BOLD}Examples:${NC}
  $0 140                      Configure VM 140 (auto-detect iGPU)
  $0 140 --pci 0000:00:02.0   Specify PCI address manually
  $0 140 --yes --start        No prompts, start VM after
EOF
    exit 0
}

detect_igpu() {
    local line
    line=$(lspci -nn | grep -iE '(vga|display|3d)' | grep -i '\[8086:' | head -1) || true

    [ -z "$line" ] && die "No Intel GPU found on this system."

    local addr
    addr=$(echo "$line" | awk '{print $1}')
    local devid
    devid=$(echo "$line" | sed -n 's/.*\[8086:\([0-9a-fA-F]\{4\}\)\].*/\1/p' | tr 'A-F' 'a-f')
    local desc
    desc=$(echo "$line" | sed 's/.*: //' | sed 's/ \[8086:.*//' | sed 's/^Intel Corporation //')

    if [[ "$addr" != *:* ]]; then
        IGPU_ADDR="0000:${addr}"
    else
        IGPU_ADDR="${addr}"
    fi

    IGPU_DEVICE_ID="$devid"
    IGPU_DESC="$desc"
}

check_needs_lpc() {
    local d
    d=$(echo "$IGPU_DESC" | tr '[:upper:]' '[:lower:]')

    if echo "$d" | grep -qiE '(ice.*lake|rocket.*lake|tiger.*lake|alder.*lake|raptor.*lake|meteor.*lake|arrow.*lake|lunar.*lake|panther.*lake|jasper.*lake|twin.*lake)'; then
        return 0
    fi

    local p="${IGPU_DEVICE_ID:0:3}"
    case "$p" in
        8a5|8a6|8a7|9a4|9a5|9a6|9a7|9ac|9ad|9af|4c8|4c9|468|469|46a|46b|46d|46e|a78|a79|a7a|a7b|7d4|7d5|7d6|4e5|4e6|4e7)
            return 0 ;;
        *)
            return 1 ;;
    esac
}

VMID=""
CUSTOM_PCI=""
ASSUME_YES=false
START_VM=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --pci)   CUSTOM_PCI="$2"; shift 2 ;;
        --rom)   ROM_DIR=$(dirname "$2"); ROM_NAME=$(basename "$2"); shift 2 ;;
        --yes)   ASSUME_YES=true; shift ;;
        --start) START_VM=true; shift ;;
        -h|--help) usage ;;
        -*)      die "Unknown option: $1 (use --help)" ;;
        *)
            if [ -z "$VMID" ]; then
                VMID="$1"
            else
                die "Unexpected argument: $1"
            fi
            shift
            ;;
    esac
done

[ -z "$VMID" ] && die "VMID is required. Usage: $0 <VMID> [OPTIONS]"
command -v qm >/dev/null 2>&1 || die "qm command not found. This script must run on a Proxmox host."
[ "$(id -u)" -ne 0 ] && die "This script must be run as root."

ROM_PATH="${ROM_DIR}/${ROM_NAME}"
[ ! -f "$ROM_PATH" ] && die "ROM file not found: $ROM_PATH\nRun igpu-rom-download.sh first, or use --rom <path>."

info "Detecting Intel iGPU..."
detect_igpu
if [ -n "$CUSTOM_PCI" ]; then
    IGPU_ADDR="$CUSTOM_PCI"
fi

ok "iGPU: $IGPU_DESC"
info "PCI: $IGPU_ADDR   Device ID: 8086:$IGPU_DEVICE_ID"
info "ROM: $ROM_PATH"

if check_needs_lpc; then
    NEEDS_LPC=true
    info "CPU generation requires x-igd-lpc=on (Ice Lake or newer)"
else
    NEEDS_LPC=false
fi

info "Reading VM $VMID config..."
CURRENT=$(qm config "$VMID" 2>/dev/null) || die "VM $VMID does not exist."
VM_STATUS=$(qm status "$VMID" 2>/dev/null | awk '{print $2}')

CUR_MACHINE=$(echo "$CURRENT" | awk -F': ' '/^machine:/{print $2}')
CUR_VGA=$(echo "$CURRENT" | awk -F': ' '/^vga:/{print $2}')
CUR_BIOS=$(echo "$CURRENT" | awk -F': ' '/^bios:/{print $2}')
CUR_ARGS=$(echo "$CURRENT" | awk -F': ' '/^args:/{print $2}')

echo ""
echo "${BOLD}=== Configuration Changes ===${NC}"
echo ""

if [ -z "$CUR_MACHINE" ] || [[ "$CUR_MACHINE" != "pc" ]]; then
    echo "  machine:  ${CUR_MACHINE:-<default>} ${YLW}->${NC} pc ${RED}(i440fx, required for legacy-igd)${NC}"
    CHANGING_MACHINE=true
else
    echo "  machine:  pc ${GRN}(already set)${NC}"
    CHANGING_MACHINE=false
fi

if [ -z "$CUR_VGA" ] || [ "$CUR_VGA" != "none" ]; then
    echo "  vga:      ${CUR_VGA:-std} ${YLW}->${NC} none ${RED}(noVNC will stop working)${NC}"
else
    echo "  vga:      none ${GRN}(already set)${NC}"
fi

if [ -z "$CUR_BIOS" ]; then
    echo "  bios:     <default> ${YLW}->${NC} ovmf"
elif [ "$CUR_BIOS" != "ovmf" ]; then
    echo "  bios:     $CUR_BIOS ${YLW}->${NC} ovmf"
else
    echo "  bios:     ovmf ${GRN}(already set)${NC}"
fi

IGPU_HOSTPCI_ENTRY=""
IGPU_HOSTPCI_SLOT=""
for slot_num in 0 1 2 3 4 5 6 7 8 9; do
    entry=$(echo "$CURRENT" | awk -F': ' "/^hostpci${slot_num}:/{print \$2}")
    if [ -n "$entry" ]; then
        entry_addr=$(echo "$entry" | cut -d',' -f1)
        if [ "$entry_addr" = "$IGPU_ADDR" ] || [ "$entry_addr" = "${IGPU_ADDR%.0}" ]; then
            IGPU_HOSTPCI_ENTRY="$entry"
            IGPU_HOSTPCI_SLOT="$slot_num"
            break
        fi
    fi
done

if [ -n "$IGPU_HOSTPCI_SLOT" ]; then
    echo "  hostpci${IGPU_HOSTPCI_SLOT}: $IGPU_HOSTPCI_ENTRY ${YLW}->${NC} ${IGPU_ADDR},legacy-igd=1,romfile=${ROM_NAME}"
else
    IGPU_HOSTPCI_SLOT=0
    existing_h0=$(echo "$CURRENT" | awk -F': ' '/^hostpci0:/{print $2}')
    if [ -n "$existing_h0" ]; then
        warn "hostpci0 is in use by another device: $existing_h0"
        warn "The iGPU will be placed on hostpci0, replacing the existing device."
        echo "  hostpci0: $existing_h0 ${RED}->${NC} ${IGPU_ADDR},legacy-igd=1,romfile=${ROM_NAME}"
    else
        echo "  hostpci0: ${YLW}(new)${NC} ${IGPU_ADDR},legacy-igd=1,romfile=${ROM_NAME}"
    fi
fi

if $NEEDS_LPC; then
    LPC_ARG="-set device.hostpci${IGPU_HOSTPCI_SLOT}.x-igd-lpc=on"
    if echo "$CUR_ARGS" | grep -q 'x-igd-lpc' 2>/dev/null; then
        echo "  args:     x-igd-lpc=on ${GRN}(already set)${NC}"
    else
        if [ -n "$CUR_ARGS" ]; then
            echo "  args:     (appending) $LPC_ARG"
        else
            echo "  args:     ${YLW}(new)${NC} $LPC_ARG"
        fi
    fi
else
    LPC_ARG=""
    echo "  args:     ${GRN}(none needed for this CPU generation)${NC}"
fi

if $CHANGING_MACHINE; then
    echo ""
    WARN_SHOWN=false
    for slot_num in 0 1 2 3 4 5 6 7 8 9; do
        [ "$slot_num" = "$IGPU_HOSTPCI_SLOT" ] && continue
        entry=$(echo "$CURRENT" | awk -F': ' "/^hostpci${slot_num}:/{print \$2}")
        if echo "$entry" | grep -q 'pcie=1' 2>/dev/null; then
            if ! $WARN_SHOWN; then
                warn "Other hostpci devices use pcie=1 which requires q35."
                WARN_SHOWN=true
            fi
            echo "         hostpci${slot_num}: $entry ${YLW}->${NC} $(echo "$entry" | sed 's/,pcie=1//; s/pcie=1,//; s/pcie=1//')"
        fi
    done
fi

echo ""
echo "${RED}Important:${NC}"
echo "  - With vga=none, Proxmox noVNC console will NOT work."
echo "    Connect a physical monitor to the motherboard video port."
echo "  - Changing machine type may cause Windows to re-detect hardware"
echo "    on first boot (extra reboot, device re-enumeration)."
echo "  - Make sure 'disable_vga=1' is NOT in /etc/modprobe.d/vfio.conf"
echo "    or kernel parameters."
echo ""

if ! $ASSUME_YES; then
    read -rp "Apply these changes to VM $VMID? [y/N] " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || die "Aborted by user."
fi

if [ "$VM_STATUS" = "running" ]; then
    info "VM is running, stopping..."
    qm shutdown "$VMID" --timeout 30 || qm stop "$VMID"
    while [ "$(qm status "$VMID" | awk '{print $2}')" = "running" ]; do
        sleep 1
    done
    ok "VM stopped."
fi

info "Applying configuration..."

qm set "$VMID" --machine pc
qm set "$VMID" --vga none

if [ -z "$CUR_BIOS" ] || [ "$CUR_BIOS" != "ovmf" ]; then
    qm set "$VMID" --bios ovmf
fi

qm set "$VMID" --hostpci${IGPU_HOSTPCI_SLOT} "${IGPU_ADDR},legacy-igd=1,romfile=${ROM_NAME}"

if $CHANGING_MACHINE; then
    for slot_num in 0 1 2 3 4 5 6 7 8 9; do
        [ "$slot_num" = "$IGPU_HOSTPCI_SLOT" ] && continue
        entry=$(echo "$CURRENT" | awk -F': ' "/^hostpci${slot_num}:/{print \$2}")
        if echo "$entry" | grep -q 'pcie=1' 2>/dev/null; then
            new_entry=$(echo "$entry" | sed 's/,pcie=1//; s/pcie=1,//; s/pcie=1//')
            qm set "$VMID" --hostpci${slot_num} "$new_entry"
            info "Updated hostpci${slot_num}: removed pcie=1"
        fi
    done
fi

if $NEEDS_LPC; then
    if [ -n "$CUR_ARGS" ] && ! echo "$CUR_ARGS" | grep -q 'x-igd-lpc'; then
        NEW_ARGS="$CUR_ARGS $LPC_ARG"
        qm set "$VMID" --args "$NEW_ARGS"
    elif [ -z "$CUR_ARGS" ]; then
        qm set "$VMID" --args "$LPC_ARG"
    fi
fi

ok "Configuration applied to VM $VMID."

if $START_VM; then
    info "Starting VM $VMID..."
    qm start "$VMID"
    ok "VM started. Check your physical monitor for display output."
else
    echo ""
    info "Start the VM with: ${BOLD}qm start $VMID${NC}"
fi
