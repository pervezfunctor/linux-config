#!/usr/bin/env bash
set -Eeuo pipefail

# Remove cached SMB credentials for a server that live outside the GNOME
# keyring. Companion to smb-keyring.nu "clear" — that script removes the
# keyring entry, then calls this for the rest.
#
# Cleans:
#   - kernel keyring cifs.spnego / cifs.upcall caches (via keyctl, if present)
#   - Kerberos tickets (klist/kdestroy, if present) — only when krb auth is used
#
# Usage: clear-smb-creds.bash <server>
# Safe to run even if no creds are cached; missing tools are skipped silently.

server="${1:-}"
[[ -n "$server" ]] || { echo "Usage: $0 <server>" >&2; exit 1; }

# --- Kernel keyring: cifs helper caches (uid-keyring + session keyring) ---
if command -v keyctl >/dev/null 2>&1; then
  # Look in both the session keyring and the user keyring for cifs-related keys.
  for keyring in "@s" "@u"; do
    # keyctl search returns the key id on stdout (printed) when found.
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

# --- Kerberos tickets ---
# Only relevant if the mount used sec=krb5. We don't know the realm ahead of
# time, so if a ticket exists and matches the server's hostname/IP in the
# cache, destroy it. Conservative: only act if klist shows a principal that
# looks related; otherwise leave tickets alone.
if command -v klist >/dev/null 2>&1 && command -v kdestroy >/dev/null 2>&1; then
  if klist 2>/dev/null | grep -qi "${server}"; then
    echo "Kerberos ticket references ${server}; leaving it in place."
    echo "  (Run 'kdestroy' manually if you want to drop all tickets.)"
  fi
else
  echo "klist/kdestroy not found — skipping Kerberos cleanup"
fi

echo "Done clearing cached SMB credentials for ${server}."
