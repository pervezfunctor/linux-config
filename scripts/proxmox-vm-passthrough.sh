#!/usr/bin/env bash
# proxmox-vm-passthrough.sh
# Interactively configures a Proxmox VM for PCIe passthrough using qm set.
# Supports:
#   - Intel iGPU legacy mode (display output from boot)
#   - Intel iGPU UPT mode (secondary GPU / QuickSync on q35)
#   - Generic PCIe device passthrough
#
# Must be run as root on the Proxmox host.

set -eEuo pipefail

# ── colours ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
die()     { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }
confirm() {
    local msg="$1" default="${2:-n}"
    local prompt
    [[ "${default,,}" == "y" ]] && prompt="[Y/n]" || prompt="[y/N]"
    read -rp "$(echo -e "${YELLOW}${msg} ${prompt}:${RESET} ")" ans
    ans="${ans:-$default}"
    [[ "${ans,,}" == "y" ]]
}

# ── root + deps ────────────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || die "Run as root."
for cmd in fzf qm lspci; do
    command -v "$cmd" &>/dev/null || die "Required command not found: $cmd"
done

# ══════════════════════════════════════════════════════════════════════════════
# STEP 1 – Pick VM
# ══════════════════════════════════════════════════════════════════════════════
pick_vm() {
    info "Loading VM list..."

    local vm_list
    vm_list=$(qm list | tail -n +2 | awk '{printf "%s  %-30s  status=%-10s  mem=%s\n", $1, $2, $3, $4}')

    [[ -z "$vm_list" ]] && die "No VMs found on this node."

    local selected
    selected=$(echo "$vm_list" | fzf \
        --prompt="Select VM > " \
        --header="ENTER to confirm" \
        --height=40% \
        --layout=reverse \
        --border) || die "No VM selected."

    VMID=$(echo "$selected" | awk '{print $1}')
    VMNAME=$(echo "$selected" | awk '{print $2}')
    ok "Selected VM: $VMID ($VMNAME)"
}

# ══════════════════════════════════════════════════════════════════════════════
# STEP 2 – Pick passthrough mode
# ══════════════════════════════════════════════════════════════════════════════
pick_mode() {
    local mode_list
    mode_list=$(cat <<'EOF'
igpu-legacy   Intel iGPU – Legacy mode  (display from boot, i440fx/pc machine, primary GPU)
igpu-upt      Intel iGPU – UPT mode     (display after driver load, q35 machine, secondary GPU)
generic       Generic PCIe device       (any device, pcie=1, manual options)
EOF
)

    local selected
    selected=$(echo "$mode_list" | fzf \
        --prompt="Select passthrough mode > " \
        --height=30% \
        --layout=reverse \
        --border) || die "No mode selected."

    MODE=$(echo "$selected" | awk '{print $1}')
    ok "Mode: $MODE"
}

# ══════════════════════════════════════════════════════════════════════════════
# STEP 3 – Pick PCIe device(s)
# ══════════════════════════════════════════════════════════════════════════════
pick_pcie_devices() {
    local multi="${1:-false}"
    local prompt="${2:-Select PCIe device}"

    info "Scanning PCIe devices..."
    local device_list
    device_list=$(lspci -Dmmnn | awk '{
        bdf=$1; $1=$2=$3=$4=""; desc=substr($0,5);
        printf "%s  %s\n", bdf, desc
    }')

    local fzf_args=(
        --prompt="${prompt} > "
        --header="ENTER to confirm"
        --height=60%
        --layout=reverse
        --border
    )
    [[ "$multi" == "true" ]] && fzf_args+=(--multi --header="TAB=select multiple  ENTER=confirm")

    local selected
    selected=$(echo "$device_list" | fzf "${fzf_args[@]}") || die "No device selected."

    SELECTED_DEVICES=()
    while IFS= read -r line; do
        local bdf
        bdf=$(echo "$line" | awk '{print $1}')
        SELECTED_DEVICES+=("$bdf")
    done <<< "$selected"

    info "Selected device(s): ${SELECTED_DEVICES[*]}"
}

# ══════════════════════════════════════════════════════════════════════════════
# STEP 4 – Show current VM config excerpt
# ══════════════════════════════════════════════════════════════════════════════
show_current_config() {
    echo ""
    echo -e "${BOLD}Current config for VM ${VMID} (${VMNAME}):${RESET}"
    qm config "$VMID" | grep -E '^(machine|bios|vga|hostpci|args|cpu):' || true
    echo ""
}

# ══════════════════════════════════════════════════════════════════════════════
# STEP 5 – Apply config
# ══════════════════════════════════════════════════════════════════════════════

apply_igpu_legacy() {
    pick_pcie_devices false "Select Intel iGPU (00:02.0)"
    local bdf="${SELECTED_DEVICES[0]}"

    # Check ROM
    local rom_opt=""
    if [[ -f "/usr/share/kvm/igd.rom" ]]; then
        ok "Found /usr/share/kvm/igd.rom"
        rom_opt=",romfile=igd.rom"
    else
        warn "No igd.rom found at /usr/share/kvm/igd.rom — run proxmox-vfio-setup.sh first."
        warn "Continuing without romfile (display output may not work)."
    fi

    # Check if hostpci0 already exists
    if qm config "$VMID" | grep -q '^hostpci0:'; then
        warn "hostpci0 already set. Removing before reconfiguring..."
        qm set "$VMID" --delete hostpci0
    fi

    info "Applying iGPU legacy passthrough config..."

    qm set "$VMID" \
        --machine pc \
        --bios ovmf \
        --vga none \
        --hostpci0 "${bdf},legacy-igd=1${rom_opt}"

    qm set "$VMID" \
        --args "-set device.hostpci0.bus=pci.0 -set device.hostpci0.addr=2.0 -set device.hostpci0.x-igd-opregion=on -set device.hostpci0.x-igd-lpc=on"

    # CPU args to prevent Code 43 / driver detection of hypervisor
    local cur_cpu
    cur_cpu=$(qm config "$VMID" | grep '^cpu:' | awk '{print $2}' || echo "host")
    # Strip any existing hidden/kvm flags before re-adding
    cur_cpu=$(echo "$cur_cpu" | sed 's/,hidden=[^,]*//g; s/,kvm=[^,]*//g')
    qm set "$VMID" --cpu "${cur_cpu},hidden=1,kvm=off"

    ok "iGPU legacy config applied."
    warn "Set 'Primary Display = iGPU' in host BIOS if display output is needed from boot."
}

apply_igpu_upt() {
    pick_pcie_devices false "Select Intel iGPU (00:02.0)"
    local bdf="${SELECTED_DEVICES[0]}"

    local rom_opt=""
    if [[ -f "/usr/share/kvm/igd.rom" ]]; then
        ok "Found /usr/share/kvm/igd.rom"
        # UPT mode uses Universal_noGOP rom ideally, but igd.rom can work too
        rom_opt=",romfile=igd.rom"
    else
        warn "No igd.rom found — UPT mode can still work without a ROM for QuickSync."
    fi

    if qm config "$VMID" | grep -q '^hostpci0:'; then
        warn "hostpci0 already set. Removing before reconfiguring..."
        qm set "$VMID" --delete hostpci0
    fi

    info "Applying iGPU UPT passthrough config..."

    qm set "$VMID" \
        --machine q35 \
        --bios ovmf \
        --hostpci0 "${bdf}${rom_opt}"

    qm set "$VMID" \
        --args "-set device.hostpci0.bus=pci.0 -set device.hostpci0.addr=2.0 -set device.hostpci0.x-igd-opregion=on"

    local cur_cpu
    cur_cpu=$(qm config "$VMID" | grep '^cpu:' | awk '{print $2}' || echo "host")
    cur_cpu=$(echo "$cur_cpu" | sed 's/,hidden=[^,]*//g; s/,kvm=[^,]*//g')
    qm set "$VMID" --cpu "${cur_cpu},hidden=1,kvm=off"

    ok "iGPU UPT config applied."
    warn "UPT: display output only works after guest drivers load. Linux guests may not get display output (use Looking Glass or remote access)."
}

apply_generic() {
    pick_pcie_devices true "Select PCIe device(s) to pass through"

    local slot=0
    for bdf in "${SELECTED_DEVICES[@]}"; do
        # Default options
        local opts="pcie=1"

        # Offer x-vga for VGA-class devices
        local class
        class=$(lspci -s "$bdf" | grep -oP '\[.{4}\]' | head -1 | tr -d '[]' || true)
        if lspci -s "$bdf" | grep -qi "VGA\|Display\|3D"; then
            if confirm "  Enable x-vga=1 for $bdf (primary GPU / VGA arbitration)?"; then
                opts="${opts},x-vga=1"
            fi
        fi

        if confirm "  Enable rombar for $bdf?"; then
            opts="${opts},rombar=1"
        fi

        info "Adding hostpci${slot}: ${bdf},${opts}"
        # Remove existing slot if present
        if qm config "$VMID" | grep -q "^hostpci${slot}:"; then
            qm set "$VMID" --delete "hostpci${slot}"
        fi
        qm set "$VMID" --hostpci${slot} "${bdf},${opts}"
        (( slot++ ))
    done

    ok "Generic passthrough config applied for ${#SELECTED_DEVICES[@]} device(s)."
}

# ══════════════════════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════════════════════
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║    Proxmox VM Passthrough Configurator   ║${RESET}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════╝${RESET}"
echo ""

pick_vm
show_current_config
pick_mode

case "$MODE" in
    igpu-legacy) apply_igpu_legacy ;;
    igpu-upt)    apply_igpu_upt ;;
    generic)     apply_generic ;;
    *)           die "Unknown mode: $MODE" ;;
esac

echo ""
echo -e "${BOLD}Final config for VM ${VMID}:${RESET}"
qm config "$VMID" | grep -E '^(machine|bios|vga|hostpci|args|cpu):'

echo ""
echo -e "${BOLD}${YELLOW}⚠  Full cold boot required:${RESET}"
echo -e "   ${CYAN}qm stop ${VMID} && shutdown -h now${RESET}"
echo -e "   Wait 20+ seconds, then power on and ${CYAN}qm start ${VMID}${RESET}"
