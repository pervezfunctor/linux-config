#!/usr/bin/env bash
set -euo pipefail

SMB_SERVER="192.168.10.56"
SMB_SHARE="share"
SMB_PATH="libvirt-vm-backups"
MOUNT_POINT="/mnt/vm-backups"

DRY_RUN=false
SHUTDOWN_TIMEOUT=120
COMPRESS=false
SMB_USER=""
SMB_PASS=""

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Backup all libvirt VMs to an SMB share (uses sudo for CIFS mount).

Options:
  -u, --user USER       SMB username (will prompt if not given)
  -p, --pass PASSWORD   SMB password (will prompt if not given)
  -c, --compress        Compress disk images with gzip
  -t, --timeout SECS    Shutdown timeout in seconds (default: 120)
  -n, --dry-run         Show what would be done without doing it
  -h, --help            Show this help
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -u|--user)    SMB_USER="$2"; shift 2 ;;
        -p|--pass)    SMB_PASS="$2"; shift 2 ;;
        -c|--compress) COMPRESS=true; shift ;;
        -t|--timeout) SHUTDOWN_TIMEOUT="$2"; shift 2 ;;
        -n|--dry-run) DRY_RUN=true; shift ;;
        -h|--help)    usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

if [[ -z "$SMB_USER" ]]; then
    read -r -p "SMB username: " SMB_USER
fi
if [[ -z "$SMB_PASS" ]]; then
    read -r -s -p "SMB password: " SMB_PASS
    echo
fi

cleanup() {
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        echo "[CLEANUP] Unmounting $MOUNT_POINT..."
        sudo umount "$MOUNT_POINT" 2>/dev/null || true
    fi
}
trap cleanup EXIT

if ! command -v virsh &>/dev/null; then
    echo "Error: virsh not found. Install libvirt-client."
    exit 1
fi

echo "[1/5] Mounting SMB share //${SMB_SERVER}/${SMB_SHARE} -> ${MOUNT_POINT}..."
sudo mkdir -p "$MOUNT_POINT"
sudo mount -t cifs "//${SMB_SERVER}/${SMB_SHARE}" "$MOUNT_POINT" \
    -o "username=${SMB_USER},password=${SMB_PASS},uid=$(id -u),gid=$(id -g),iocharset=utf8,noperm"
echo "  OK"

BACKUP_DIR="${MOUNT_POINT}/${SMB_PATH}/$(date +%Y%m%d_%H%M%S)"

mapfile -t VMS < <(virsh list --all --name | grep -v '^$')
TOTAL=${#VMS[@]}

if [[ $TOTAL -eq 0 ]]; then
    echo "[2/5] No VMs found. Nothing to do."
    exit 0
fi

echo "[2/5] Found $TOTAL VM(s):"
for vm in "${VMS[@]}"; do
    state=$(virsh domstate "$vm" 2>/dev/null || echo "?")
    echo "       - $vm ($state)"
done

echo "[3/5] Creating backup directory..."
$DRY_RUN || mkdir -p "$BACKUP_DIR"
echo "       $BACKUP_DIR"

echo "[4/5] Backing up VMs..."
RESULTS=()
CURRENT=0

for VM in "${VMS[@]}"; do
    CURRENT=$((CURRENT + 1))
    STATUS="OK"
    VM_DIR="$BACKUP_DIR/$VM"
    START_TS=$(date +%s)

    printf "  [%02d/%02d] %s ... " "$CURRENT" "$TOTAL" "$VM"

    if ! $DRY_RUN; then
        mkdir -p "$VM_DIR"
    fi

    # Save XML config
    if ! $DRY_RUN; then
        virsh dumpxml "$VM" > "$VM_DIR/${VM}.xml" 2>/dev/null
    fi

    STATE=$(virsh domstate "$VM" 2>/dev/null || echo "unknown")
    WAS_RUNNING=false

    if [[ "$STATE" == "running" ]]; then
        WAS_RUNNING=true
        printf "(shutting down...) "
        $DRY_RUN || virsh shutdown "$VM" &>/dev/null || true

        for ((i=0; i<SHUTDOWN_TIMEOUT; i++)); do
            S=$(virsh domstate "$VM" 2>/dev/null || echo "unknown")
            [[ "$S" != "running" ]] && break
            sleep 1
        done

        S=$(virsh domstate "$VM" 2>/dev/null || echo "unknown")
        if [[ "$S" == "running" ]]; then
            echo "(forcing...) "
            $DRY_RUN || virsh destroy "$VM" &>/dev/null || true
        fi
    fi

    # Copy disk images
    DISK_OK=0
    DISK_TOTAL=0
    while read -r type device target source; do
        [[ "$type" != "file" ]] && continue
        [[ "$source" == "-" ]] && continue
        DISK_TOTAL=$((DISK_TOTAL + 1))
        DISK_NAME="${VM}-${target}"
        EXT="${source##*.}"
        [[ "$source" == "$EXT" ]] && EXT="img"

        if [[ "$COMPRESS" == "true" ]]; then
            DEST="${VM_DIR}/${DISK_NAME}.${EXT}.gz"
        else
            DEST="${VM_DIR}/${DISK_NAME}.${EXT}"
        fi

        if ! $DRY_RUN && [[ -f "$source" ]]; then
            if [[ "$COMPRESS" == "true" ]]; then
                gzip -c "$source" > "$DEST"
            else
                rsync --progress --sparse "$source" "$DEST"
            fi
            DISK_OK=$((DISK_OK + 1))
        fi
    done < <(virsh domblklist "$VM" --details 2>/dev/null | tail -n +3)

    if [[ $DISK_TOTAL -eq 0 ]]; then
        printf "(no disks) "
    fi

    if [[ $DISK_OK -lt $DISK_TOTAL ]]; then
        STATUS="WARN (disks: $DISK_OK/$DISK_TOTAL)"
    fi

    # Restart VM if it was running
    if [[ "$WAS_RUNNING" == true ]]; then
        $DRY_RUN || virsh start "$VM" &>/dev/null || true
    fi

    ELAPSED=$(( $(date +%s) - START_TS ))
    RESULTS+=("$VM|$STATUS|${ELAPSED}s|${DISK_OK}/${DISK_TOTAL} disks")

    if [[ "$DRY_RUN" == true ]]; then
        printf "DRY-RUN\n"
    else
        printf "done (%s, %s, %s)\n" "$ELAPSED" "${DISK_OK}/${DISK_TOTAL} disks" "$STATUS"
    fi
done

echo "[5/5] Summary"
printf "  %-35s %-8s %-10s %s\n" "VM" "RESULT" "TIME" "DISKS"
printf "  %-35s %-8s %-10s %s\n" "-----------------------------------" "--------" "----------" "-----"
for r in "${RESULTS[@]}"; do
    IFS='|' read -r vm result elapsed disks <<< "$r"
    printf "  %-35s %-8s %-10s %s\n" "$vm" "$result" "$elapsed" "$disks"
done

if ! $DRY_RUN; then
    TOTAL_SIZE=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1 || echo "?")
    echo ""
    echo "Backup complete: $BACKUP_DIR (total: $TOTAL_SIZE)"
    echo "Disk usage per VM:"
    du -sh "$BACKUP_DIR"/*/ 2>/dev/null | while read -r size path; do
        echo "  $(basename "$path"): $size"
    done
fi
