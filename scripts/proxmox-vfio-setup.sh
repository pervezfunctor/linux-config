#!/usr/bin/env bash
# proxmox-vfio-setup.sh
# Sets up VFIO passthrough on a Proxmox host:
#   - Enables IOMMU in GRUB
#   - Blacklists selected device drivers
#   - Binds selected PCIe devices to vfio-pci
#   - Downloads the correct Intel iGPU ROM (optional)
#
# Must be run as root on the Proxmox host.

set -eEuo pipefail

# ── colours ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()  { echo -e "${CYAN}[INFO]${RESET}  $*"; }
ok()    { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
die()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }

# ── root check ─────────────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || die "Run as root."

# ── dependency check ───────────────────────────────────────────────────────────
for cmd in fzf lspci curl hexdump update-grub update-initramfs; do
    command -v "$cmd" &>/dev/null || die "Required command not found: $cmd  (apt install $cmd)"
done

# ══════════════════════════════════════════════════════════════════════════════
# STEP 1 – IOMMU / GRUB
# ══════════════════════════════════════════════════════════════════════════════
setup_iommu() {
    info "Configuring IOMMU in GRUB..."

    local grub_file="/etc/default/grub"
    cp "$grub_file" "${grub_file}.bak.$(date +%s)"

    # Detect Intel vs AMD
    local vendor
    vendor=$(grep -m1 'vendor_id' /proc/cpuinfo | awk '{print $3}')

    local iommu_param
    if [[ "$vendor" == "GenuineIntel" ]]; then
        iommu_param="intel_iommu=on iommu=pt"
    else
        iommu_param="amd_iommu=on iommu=pt"
    fi

    # Inject into GRUB_CMDLINE_LINUX_DEFAULT if not already present
    if grep -q "iommu=pt" "$grub_file"; then
        ok "IOMMU params already present in GRUB."
    else
        sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=\"|GRUB_CMDLINE_LINUX_DEFAULT=\"${iommu_param} |" "$grub_file"
        ok "Added: $iommu_param"
    fi

    update-grub 2>/dev/null || true
}

# ══════════════════════════════════════════════════════════════════════════════
# STEP 2 – Load VFIO modules at boot
# ══════════════════════════════════════════════════════════════════════════════
setup_vfio_modules() {
    info "Ensuring vfio modules load at boot..."

    local modules_file="/etc/modules"
    local needed=(vfio vfio_iommu_type1 vfio_pci)

    for mod in "${needed[@]}"; do
        if ! grep -qx "$mod" "$modules_file" 2>/dev/null; then
            echo "$mod" >> "$modules_file"
            ok "Added module: $mod"
        else
            ok "Module already listed: $mod"
        fi
    done
}

# ══════════════════════════════════════════════════════════════════════════════
# STEP 3 – fzf device picker → vfio-pci IDs + driver blacklist
# ══════════════════════════════════════════════════════════════════════════════
pick_devices() {
    info "Scanning PCIe devices (fzf multi-select, TAB to select, ENTER to confirm)..."
    echo ""

    # Build a list: "BDF  [VENDOR:DEVICE]  Description  (driver)"
    local device_list
    device_list=$(lspci -Dmmnn | awk '{
        bdf=$1; class=$2; vendor=$3; device=$4;
        $1=$2=$3=$4=""; desc=substr($0,5);
        gsub(/\[|\]/, "", vendor); gsub(/\[|\]/, "", device);
        printf "%s  [%s:%s]  %s\n", bdf, vendor, device, desc
    }')

    local selected
    selected=$(echo "$device_list" | fzf \
        --multi \
        --prompt="Select devices to bind to vfio-pci > " \
        --header="TAB=select  ENTER=confirm  ESC=cancel" \
        --height=60% \
        --layout=reverse \
        --border) || { warn "No devices selected."; return; }

    [[ -z "$selected" ]] && { warn "No devices selected."; return; }

    # Extract vendor:device IDs
    local ids=()
    local drivers_to_blacklist=()

    while IFS= read -r line; do
        local bdf vid_did
        bdf=$(echo "$line" | awk '{print $1}')
        vid_did=$(echo "$line" | grep -oP '\[\K[0-9a-f]{4}:[0-9a-f]{4}(?=\])')

        ids+=("$vid_did")

        # Find current driver
        local driver
        driver=$(lspci -k -s "$bdf" 2>/dev/null | grep "Kernel driver in use:" | awk '{print $NF}' || true)
        if [[ -n "$driver" && "$driver" != "vfio-pci" ]]; then
            drivers_to_blacklist+=("$driver")
            info "  $bdf → $vid_did (current driver: $driver)"
        else
            info "  $bdf → $vid_did"
        fi
    done <<< "$selected"

    # Write vfio.conf
    local vfio_conf="/etc/modprobe.d/vfio.conf"
    local ids_joined
    ids_joined=$(IFS=,; echo "${ids[*]}")

    # Preserve existing IDs if any
    local existing_ids=""
    if [[ -f "$vfio_conf" ]]; then
        existing_ids=$(grep -oP '(?<=ids=)[^\s]+' "$vfio_conf" || true)
    fi

    if [[ -n "$existing_ids" ]]; then
        ids_joined="${existing_ids},${ids_joined}"
        # Deduplicate
        ids_joined=$(echo "$ids_joined" | tr ',' '\n' | sort -u | tr '\n' ',' | sed 's/,$//')
    fi

    cat > "$vfio_conf" <<EOF
# Generated by proxmox-vfio-setup.sh on $(date)
options vfio-pci ids=${ids_joined}
# Note: disable_vga=1 is intentionally omitted (breaks Intel iGPU passthrough)
EOF
    ok "Written: $vfio_conf  (ids=${ids_joined})"

    # Write blacklist
    if [[ ${#drivers_to_blacklist[@]} -gt 0 ]]; then
        local blacklist_file="/etc/modprobe.d/vfio-blacklist.conf"
        # Deduplicate drivers
        local unique_drivers
        unique_drivers=$(printf '%s\n' "${drivers_to_blacklist[@]}" | sort -u)

        {
            echo "# Generated by proxmox-vfio-setup.sh on $(date)"
            while IFS= read -r drv; do
                echo "blacklist $drv"
            done <<< "$unique_drivers"
        } > "$blacklist_file"
        ok "Written: $blacklist_file"
        while IFS= read -r drv; do
            warn "  Blacklisted driver: $drv"
        done <<< "$unique_drivers"
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# STEP 4 – Intel iGPU ROM download
# ══════════════════════════════════════════════════════════════════════════════

# Map of gen name → ROM filename on GitHub releases
declare -A ROM_MAP=(
    ["SNB/IVB (6th/7th gen Sandy/Ivy Bridge)"]="SNB_IVB_GOPv6.1_igd.rom"
    ["HSW/BDW (8th/9th gen Haswell/Broadwell)"]="HSW_BDW_GOPv8_igd.rom"
    ["SKL/KBL/CML (10th/11th gen Skylake–Comet Lake)"]="SKL_CML_GOPv9_igd.rom"
    ["RKL/TGL/ADL/RPL (11th–14th gen Tiger–Raptor Lake)"]="RKL_TGL_ADL_RPL_GOPv17.1_igd.rom"
    ["Universal noGOP (last resort / SR-IOV VFs)"]="Universal_noGOP_igd.rom"
)

RELEASE_BASE="https://github.com/LongQT-sea/intel-igpu-passthru/releases/download/v0.1"

download_igpu_rom() {
    echo ""
    info "Intel iGPU ROM download"
    echo -e "  ${BOLD}Skip this step if you have no Intel iGPU to pass through.${RESET}"
    echo ""

    # Auto-detect CPU generation from model name
    local cpu_model
    cpu_model=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs)
    info "Detected CPU: $cpu_model"

    local auto_rom=""
    if echo "$cpu_model" | grep -qiE "14[0-9]{3}|13[0-9]{3}|12[0-9]{3}|11[0-9]{3}.*[KHF]"; then
        auto_rom="RKL/TGL/ADL/RPL (11th–14th gen Tiger–Raptor Lake)"
    elif echo "$cpu_model" | grep -qiE "10[0-9]{3}|Core i[0-9]-(10|11)"; then
        auto_rom="SKL/KBL/CML (10th/11th gen Skylake–Comet Lake)"
    fi

    if [[ -n "$auto_rom" ]]; then
        info "Auto-suggested ROM: ${auto_rom}"
    fi

    local choice
    choice=$(printf '%s\n' "${!ROM_MAP[@]}" | sort | fzf \
        --prompt="Select iGPU ROM generation > " \
        --header="Auto-detected: ${auto_rom:-unknown}" \
        --height=40% \
        --layout=reverse \
        --border \
        --select-1 ${auto_rom:+--query="$auto_rom"}) || { warn "ROM download skipped."; return; }

    local rom_file="${ROM_MAP[$choice]}"
    local dest="/usr/share/kvm/igd.rom"
    local url="${RELEASE_BASE}/${rom_file}"

    info "Downloading: $rom_file → $dest"
    curl -fsSL "$url" -o "$dest" || die "Download failed: $url"

    # Validate PCI option ROM magic
    local magic
    magic=$(hexdump -n 2 -e '2/1 "%02x "' "$dest" | xargs)
    if [[ "$magic" == "55 aa" ]]; then
        ok "ROM valid (55 aa magic confirmed): $dest"
    else
        die "ROM invalid — bad magic bytes: $magic (expected 55 aa)"
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# STEP 5 – initramfs update
# ══════════════════════════════════════════════════════════════════════════════
finish() {
    info "Updating initramfs..."
    update-initramfs -u -k all 2>&1 | tail -5
    ok "Done."
    echo ""
    echo -e "${BOLD}${YELLOW}⚠  A full cold boot is required for changes to take effect.${RESET}"
    echo -e "   Run: ${CYAN}shutdown -h now${RESET}  then power on after 20+ seconds."
}

# ══════════════════════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════════════════════
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║    Proxmox VFIO Setup                    ║${RESET}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════╝${RESET}"
echo ""

setup_iommu
setup_vfio_modules
pick_devices

echo ""
read -rp "$(echo -e "${CYAN}Download Intel iGPU ROM? [y/N]:${RESET} ")" do_rom
if [[ "${do_rom,,}" == "y" ]]; then
    download_igpu_rom
fi

finish
