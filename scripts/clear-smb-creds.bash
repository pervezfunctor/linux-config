#!/usr/bin/env bash
set -Eeuo pipefail

# Companion to smb-keyring.nu "clear": wipes cached SMB credentials for a
# server that live outside the GNOME keyring (kernel keyring, krb tickets).
# Usage: clear-smb-creds.bash <server>

server="${1:-}"
[[ -n "$server" ]] || { echo "Usage: $0 <server>" >&2; exit 1; }

if command -v keyctl >/dev/null 2>&1; then
  for keyring in "@s" "@u"; do
    while read -r kid; do
      [[ -n "$kid" ]] || continue
      keyctl revoke "$kid" 2>/dev/null && keyctl unlink "$kid" "$keyring" 2>/dev/null && \
        echo "Revoked kernel key $kid from $keyring"
    done < <(keyctl search "$keyring" keyring cifs.spnego.* 2>/dev/null; \
             keyctl search "$keyring" keyring "cifs.idmap.*" 2>/dev/null; \
             keyctl search "$keyring" user "cifs.*${server}*" 2>/dev/null)
  done
else
  echo "keyctl not found — skipping kernel keyring cleanup"
fi

if command -v klist >/dev/null 2>&1 && command -v kdestroy >/dev/null 2>&1; then
  if klist 2>/dev/null | grep -qi "${server}"; then
    echo "Kerberos ticket references ${server}; leaving it in place."
    echo "  (Run 'kdestroy' manually if you want to drop all tickets.)"
  fi
else
  echo "klist/kdestroy not found — skipping Kerberos cleanup"
fi

echo "Done clearing cached SMB credentials for ${server}."
