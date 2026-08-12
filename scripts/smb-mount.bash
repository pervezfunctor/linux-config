#!/usr/bin/env bash
set -Eeuo pipefail

# Mount a Samba share from 192.168.10.56 via kernel cifs.
# Credentials are read from the GNOME keyring (see smb-keyring.nu),
# so no password is ever typed or stored here.
#
# Usage:
#   smb-mount.bash mount <share>            # mount //SERVER/<share>
#   smb-mount.bash umount <share>           # unmount
#   smb-mount.bash status [<share>]         # show what's mounted
#   smb-mount.bash list                     # list shares on the server (needs keyring creds)
#   smb-mount.bash help
#
# Defaults: SERVER=192.168.10.56 USER=piqbal DOMAIN=WORKGROUP
# Override via env: SMB_SERVER, SMB_USER, SMB_DOMAIN, SMB_MOUNT_ROOT

SERVER="${SMB_SERVER:-192.168.10.56}"
USER_DEFAULT="piqbal"
DOMAIN="${SMB_DOMAIN:-WORKGROUP}"
MOUNT_ROOT="${SMB_MOUNT_ROOT:-/mnt/nas}"

# Real uid/gid so mounted files are owned by the invoking user.
UID_OPT="$(id -u)"
GID_OPT="$(id -g)"

die() { echo "Error: $*" >&2; exit 1; }

need_root() {
  if [[ $EUID -ne 0 ]]; then
    exec sudo -E -- "$0" "$@"
  fi
}

mountpoint_for() { echo "${MOUNT_ROOT}/$1"; }

fetch_pass() {
  local user="$1"
  local pass
  pass="$(secret-tool lookup protocol smb server "${SERVER}" user "${user}" 2>/dev/null || true)"
  [[ -n "$pass" ]] || die "No keyring credential for ${user}@${SERVER}.
Store one first:  ~/.linux-config/scripts/smb-keyring.nu store ${SERVER} ${user}"
  printf '%s' "$pass"
}

cmd_mount() {
  local share="$1"
  local user="${SMB_USER:-$USER_DEFAULT}"
  local mp; mp="$(mountpoint_for "$share")"
  mountpoint -q "$mp" && { echo "Already mounted: $mp"; return 0; }

  local pass; pass="$(fetch_pass "$user")"

  mkdir -p "$mp"
  # Pass password via a credentials file (mode 600) instead of the command
  # line, so it never shows in ps / shell history.
  local cred; cred="$(mktemp)"
  trap 'shred -u "$cred" 2>/dev/null || rm -f "$cred"' RETURN
  printf 'username=%s\npassword=%s\ndomain=%s\n' "$user" "$pass" "$DOMAIN" > "$cred"
  chmod 600 "$cred"

  # vers=3.0 matches modern TrueNAS; sec left to negotiate (drop ntlmssp).
  mount -t cifs "//${SERVER}/${share}" "$mp" \
    -o "credentials=${cred},uid=${UID_OPT},gid=${GID_OPT},iocharset=utf8,vers=3.0"
  echo "Mounted //${SERVER}/${share} at ${mp}"
}

cmd_umount() {
  local share="$1"
  local mp; mp="$(mountpoint_for "$share")"
  mountpoint -q "$mp" || { echo "Not mounted: $mp"; return 0; }
  umount "$mp"
  echo "Unmounted ${mp}"
}

cmd_status() {
  local share="${1:-}"
  if [[ -n "$share" ]]; then
    local mp; mp="$(mountpoint_for "$share")"
    if mountpoint -q "$mp"; then
      echo "mounted: ${mp}  ->  //${SERVER}/${share}"
    else
      echo "not mounted: ${mp}"
    fi
    return
  fi
  if [[ -d "$MOUNT_ROOT" ]]; then
    echo "Mounts under ${MOUNT_ROOT}:"
    findmnt -t cifs -o TARGET,SOURCE -n | grep "${MOUNT_ROOT}/" || echo "  (none)"
  else
    echo "No ${MOUNT_ROOT} directory yet."
  fi
}

cmd_list() {
  local user="${SMB_USER:-$USER_DEFAULT}"
  local pass; pass="$(fetch_pass "$user")"
  PASSWD="$pass" smbclient -L "//${SERVER}" -U "${user}" -W "${DOMAIN}" 2>&1 | sed 's/[[:space:]]*$//'
}

usage() {
  cat <<EOF
Usage: $0 <command> [share]

Commands:
  mount  <share>   Mount //${SERVER}/<share> at ${MOUNT_ROOT}/<share>
  umount <share>   Unmount
  status [<share>] Show mount status (all shares if none given)
  list             List shares on ${SERVER} (uses keyring creds)
  help             Show this help

Env overrides:
  SMB_SERVER   (default ${SERVER})
  SMB_USER     (default ${USER_DEFAULT})
  SMB_DOMAIN   (default ${DOMAIN})
  SMB_MOUNT_ROOT (default ${MOUNT_ROOT})

Examples:
  $0 mount share
  $0 umount share
  $0 status
  SMB_USER=pervez $0 mount media

Credentials are read from the GNOME keyring via secret-tool.
Store them once with:  ~/.linux-config/scripts/smb-keyring.nu store ${SERVER} ${USER_DEFAULT}
EOF
}

main() {
  local cmd="${1:-help}"; shift || true
  case "$cmd" in
    mount)
      [[ $# -ge 1 ]] || die "mount needs a share name. See: $0 help"
      need_root mount "$@"
      ;;
    umount|unmount)
      [[ $# -ge 1 ]] || die "umount needs a share name. See: $0 help"
      need_root umount "$@"
      ;;
    status)
      # status/list don't strictly need root, but mount paths under /mnt may.
      cmd_status "${1:-}"
      ;;
    list)
      cmd_list
      ;;
    help|-h|--help)
      usage
      ;;
    *)
      die "Unknown command: $cmd. See: $0 help"
      ;;
  esac
}

main "$@"
