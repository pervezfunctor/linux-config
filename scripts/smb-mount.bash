#!/usr/bin/env bash
set -Eeuo pipefail

# Mount a Samba share from 192.168.10.56 via kernel cifs.
# Credentials are read from the GNOME keyring (see smb-keyring.nu).
#
# Usage:
#   smb-mount.bash mount <share>
#   smb-mount.bash umount <share>
#   smb-mount.bash status [<share>]
#   smb-mount.bash list
#   smb-mount.bash help
#
# Override defaults via env: SMB_SERVER, SMB_USER, SMB_DOMAIN, SMB_MOUNT_ROOT

SERVER="${SMB_SERVER:-192.168.10.56}"
USER_DEFAULT="piqbal"
DOMAIN="${SMB_DOMAIN:-WORKGROUP}"
MOUNT_ROOT="${SMB_MOUNT_ROOT:-/mnt/nas}"

UID_OPT="$(id -u)"
GID_OPT="$(id -g)"

_CRED_FILE=""

die() { echo "Error: $*" >&2; exit 1; }

cleanup_cred() {
  if [[ -n "${_CRED_FILE:-}" && -f "${_CRED_FILE:-}" ]]; then
    shred -u "$_CRED_FILE" 2>/dev/null || rm -f "$_CRED_FILE"
  fi
}
trap cleanup_cred EXIT

mountpoint_for() { echo "${MOUNT_ROOT}/$1"; }

fetch_pass() {
  local user="$1"
  local pass
  pass="$(secret-tool lookup protocol smb server "${SERVER}" user "${user}" 2>/dev/null || true)"
  [[ -n "$pass" ]] || die "No keyring credential for ${user}@${SERVER}.
Store one first:  ~/.linux-config/scripts/smb-keyring.nu store ${SERVER} ${user}"
  printf '%s' "$pass"
}

write_cred_file() {
  local user="$1" pass="$2" domain="$3"
  local cred; cred="$(mktemp)"
  printf 'username=%s\npassword=%s\ndomain=%s\n' "$user" "$pass" "$domain" > "$cred"
  chmod 600 "$cred"
  echo "$cred"
}

cmd_mount() {
  local share="$1"
  local user="${SMB_USER:-$USER_DEFAULT}"
  local mp; mp="$(mountpoint_for "$share")"

  if [[ $EUID -eq 0 ]]; then
    local cred="${SMB_CRED_FILE:?internal: SMB_CRED_FILE not set}"
    local invoker_uid="${SUDO_UID:-0}" invoker_gid="${SUDO_GID:-0}"
    mountpoint -q "$mp" && { echo "Already mounted: $mp"; return 0; }
    mkdir -p "$mp"
    mount -t cifs "//${SERVER}/${share}" "$mp" \
      -o "credentials=${cred},uid=${invoker_uid},gid=${invoker_gid},iocharset=utf8,vers=3.0"
    echo "Mounted //${SERVER}/${share} at ${mp}"
    return
  fi

  mountpoint -q "$mp" 2>/dev/null && { echo "Already mounted: $mp"; return 0; }
  local pass; pass="$(fetch_pass "$user")"
  _CRED_FILE="$(write_cred_file "$user" "$pass" "$DOMAIN")"
  SMB_CRED_FILE="$_CRED_FILE" sudo -E -- "$0" mount "$share"
}

cmd_umount() {
  local share="$1"
  local mp; mp="$(mountpoint_for "$share")"
  if [[ $EUID -ne 0 ]]; then
    exec sudo -E -- "$0" umount "$share"
  fi
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
  SMB_SERVER     (default ${SERVER})
  SMB_USER       (default ${USER_DEFAULT})
  SMB_DOMAIN     (default ${DOMAIN})
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
      cmd_mount "$1"
      ;;
    umount|unmount)
      [[ $# -ge 1 ]] || die "umount needs a share name. See: $0 help"
      cmd_umount "$1"
      ;;
    status)
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
