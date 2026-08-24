#!/usr/bin/env bash
set -euo pipefail

BASE_URL="https://github.com/LongQT-sea/intel-igpu-passthru/releases/download/v0.1"
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
${BOLD}Intel iGPU OpROM Downloader${NC}
Downloads the correct Intel GOP OpROM for GVT-d passthrough.
Source: https://github.com/LongQT-sea/intel-igpu-passthru

${BOLD}Usage:${NC}
  $0 [OPTIONS]

${BOLD}Options:${NC}
  --list              List all available ROM files
  --rom <file>        Manually specify ROM file (skip auto-detection)
  --dir <path>        Target directory (default: $ROM_DIR)
  --name <file>       Output filename (default: $ROM_NAME)
  -h, --help          Show this help

${BOLD}Examples:${NC}
  $0                                      Auto-detect and download
  $0 --list                               Show all ROM files
  $0 --rom ADL-H_RPL-H_GOPv21_igd.rom     Download specific ROM
EOF
    exit 0
}

list_roms() {
    cat <<EOF
${BOLD}Available ROM files:${NC}

  ROM File                                      Description
  ----------------------------------------------------------------------------
  SNB_GOPv2_igd.rom                             Sandy Bridge (2nd gen)
  IVB_GOPv3_igd.rom                             Ivy Bridge (3rd gen)
  HSW_BDW_GOPv5_igd.rom                         Haswell/Broadwell (4th/5th gen)
  SKL_CML_GOPv9_igd.rom                         Skylake-Kaby Lake (6th-7th gen)
  CFL_CML_GOPv9.1_igd.rom                       Coffee/Comet Lake (8th-10th gen)
  GLK_GOPv13_igd.rom                            Gemini Lake
  ICL_GOPv14_igd.rom                            Ice Lake (10th gen mobile)
  RKL_TGL_ADL_RPL_GOPv17_igd.rom                Rocket/Tiger/Alder/RPL desktop
  RKL_TGL_ADL_RPL_GOPv17.1_igd.rom              Rocket/Tiger/Alder/RPL desktop
  ADL-H_RPL-H_GOPv21_igd.rom                    Alder/Raptor Lake mobile (H/P/U)
  ADL-N_TWL_GOPv21_igd.rom                      Alder Lake-N / Twin Lake
  JSL_GOPv18_igd.rom                            Jasper Lake
  ARL_MTL_GOPv22_igd.rom                        Arrow Lake / Meteor Lake
  LNL_GOPv2X_igd.rom                            Lunar Lake
  PTL-H_igd.rom                                 Panther Lake-H
  Universal_noGOP_igd.rom                       Universal fallback (no GOP)

Source: https://github.com/LongQT-sea/intel-igpu-passthru
EOF
    exit 0
}

detect_igpu() {
    local line
    line=$(lspci -nn | grep -iE '(vga|display|3d)' | grep -i '\[8086:' | head -1) || true

    [ -z "$line" ] && die "No Intel GPU found on this system."

    PCI_ADDR=$(echo "$line" | awk '{print $1}')
    DEVICE_ID=$(echo "$line" | sed -n 's/.*\[8086:\([0-9a-fA-F]\{4\}\)\].*/\1/p' | tr 'A-F' 'a-f')
    GPU_DESC=$(echo "$line" | sed 's/.*: //' | sed 's/ \[8086:.*//' | sed 's/^Intel Corporation //')
}

detect_rom_by_name() {
    local d
    d=$(echo "$GPU_DESC" | tr '[:upper:]' '[:lower:]')

    if   echo "$d" | grep -qi 'panther';                     then echo "PTL-H_igd.rom"
    elif echo "$d" | grep -qi 'lunar';                       then echo "LNL_GOPv2X_igd.rom"
    elif echo "$d" | grep -qiE '(arrow|meteor)';             then echo "ARL_MTL_GOPv22_igd.rom"
    elif echo "$d" | grep -qi 'twin';                        then echo "ADL-N_TWL_GOPv21_igd.rom"
    elif echo "$d" | grep -qiE 'alder.*lake.*[- ]?n';        then echo "ADL-N_TWL_GOPv21_igd.rom"
    elif echo "$d" | grep -qiE '(alder|raptor).*lake.*[- ]?[phu]'; then echo "ADL-H_RPL-H_GOPv21_igd.rom"
    elif echo "$d" | grep -qiE '(raptor|alder).*lake';       then echo "RKL_TGL_ADL_RPL_GOPv17.1_igd.rom"
    elif echo "$d" | grep -qiE '(tiger|rocket).*lake';       then echo "RKL_TGL_ADL_RPL_GOPv17_igd.rom"
    elif echo "$d" | grep -qi 'ice.*lake';                   then echo "ICL_GOPv14_igd.rom"
    elif echo "$d" | grep -qi 'jasper';                      then echo "JSL_GOPv18_igd.rom"
    elif echo "$d" | grep -qi 'gemini';                      then echo "GLK_GOPv13_igd.rom"
    elif echo "$d" | grep -qiE '(coffee|comet).*lake';       then echo "CFL_CML_GOPv9.1_igd.rom"
    elif echo "$d" | grep -qiE '(kaby|skylake)';             then echo "SKL_CML_GOPv9_igd.rom"
    elif echo "$d" | grep -qi 'broadwell';                   then echo "HSW_BDW_GOPv5_igd.rom"
    elif echo "$d" | grep -qi 'haswell';                     then echo "HSW_BDW_GOPv5_igd.rom"
    elif echo "$d" | grep -qi 'ivy.*bridge';                 then echo "IVB_GOPv3_igd.rom"
    elif echo "$d" | grep -qi 'sandy.*bridge';               then echo "SNB_GOPv2_igd.rom"
    else return 1
    fi
}

detect_rom_by_id() {
    local id="$1"
    local p="${id:0:3}"
    case "$p" in
        010|011|012)               echo "SNB_GOPv2_igd.rom" ;;
        015|016)                   echo "IVB_GOPv3_igd.rom" ;;
        040|041|042|0a0|0a1|0a2|0d0) echo "HSW_BDW_GOPv5_igd.rom" ;;
        160|161|162|163)           echo "HSW_BDW_GOPv5_igd.rom" ;;
        190|191|192|193)           echo "HSW_BDW_GOPv5_igd.rom" ;;
        22b)                       echo "HSW_BDW_GOPv5_igd.rom" ;;
        590|591|592|593)           echo "SKL_CML_GOPv9_igd.rom" ;;
        3e0|3e1|3e2|3e3|3e9|3ea|3eb) echo "CFL_CML_GOPv9.1_igd.rom" ;;
        9bc|9bd)                   echo "CFL_CML_GOPv9.1_igd.rom" ;;
        318)                       echo "GLK_GOPv13_igd.rom" ;;
        8a5|8a6|8a7)               echo "ICL_GOPv14_igd.rom" ;;
        9a4|9a5|9a6|9a7)           echo "RKL_TGL_ADL_RPL_GOPv17_igd.rom" ;;
        9ac|9ad|9af)               echo "RKL_TGL_ADL_RPL_GOPv17_igd.rom" ;;
        4c8|4c9)                   echo "RKL_TGL_ADL_RPL_GOPv17_igd.rom" ;;
        468|469)                   echo "RKL_TGL_ADL_RPL_GOPv17.1_igd.rom" ;;
        46a|46b)                   echo "ADL-H_RPL-H_GOPv21_igd.rom" ;;
        46d|46e)                   echo "ADL-N_TWL_GOPv21_igd.rom" ;;
        a78|a79)                   echo "RKL_TGL_ADL_RPL_GOPv17.1_igd.rom" ;;
        a7a|a7b)                   echo "ADL-H_RPL-H_GOPv21_igd.rom" ;;
        7d4|7d5|7d6)               echo "ARL_MTL_GOPv22_igd.rom" ;;
        4e5|4e6|4e7)               echo "JSL_GOPv18_igd.rom" ;;
        *) return 1 ;;
    esac
}

CUSTOM_ROM=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --list)  list_roms ;;
        --rom)   CUSTOM_ROM="$2"; shift 2 ;;
        --dir)   ROM_DIR="$2"; shift 2 ;;
        --name)  ROM_NAME="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) die "Unknown option: $1 (use --help)" ;;
    esac
done

[ "$(id -u)" -ne 0 ] && die "This script must be run as root (need write access to $ROM_DIR)."

info "Detecting Intel iGPU..."
detect_igpu
ok "Found: $GPU_DESC"
info "PCI: $PCI_ADDR   Device ID: 8086:$DEVICE_ID"

if [ -n "$CUSTOM_ROM" ]; then
    ROM_FILE="$CUSTOM_ROM"
    info "Using manually specified ROM: $ROM_FILE"
else
    ROM_FILE=$(detect_rom_by_name || true)

    if [ -z "$ROM_FILE" ]; then
        warn "Name-based detection failed, trying device ID 8086:$DEVICE_ID..."
        ROM_FILE=$(detect_rom_by_id "$DEVICE_ID" || true)
    fi

    if [ -z "$ROM_FILE" ]; then
        echo ""
        warn "Could not auto-detect ROM for this GPU."
        warn "Device ID: 8086:$DEVICE_ID   Description: $GPU_DESC"
        echo ""
        warn "Run '$0 --list' to see available ROMs."
        warn "Then use: $0 --rom <rom_file>"
        die "Auto-detection failed."
    fi

    ok "Matched ROM: $ROM_FILE"
fi

DEST="${ROM_DIR}/${ROM_NAME}"
URL="${BASE_URL}/${ROM_FILE}"

info "Downloading to: $DEST"
mkdir -p "$ROM_DIR"
curl -fL "$URL" -o "$DEST"

if [ -f "$DEST" ]; then
    SIZE=$(stat -c%s "$DEST" 2>/dev/null || stat -f%z "$DEST" 2>/dev/null || echo "?")
    ok "Downloaded successfully (${SIZE} bytes)"
    echo ""
    info "Next step: run ${BOLD}igpu-vm-setup.sh <VMID>${NC} to configure your VM."
fi
