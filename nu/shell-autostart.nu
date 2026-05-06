#!/usr/bin/env nu

use ./lib.nu *

def main [shell: string, rc: string] {
  log+ $"Setting ($shell) auto-start in ($rc)"

  warn+ "This might break certain software, that don't correctly invoke shells as non-interactive."

  let rc_path = ($env.HOME | path join $rc)
  let marker = $"exec ($shell)"
  let launched_var = $"(($shell | str upcase))_LAUNCHED"

  let snippet = $"
# Auto-start ($shell) for interactive shells
if [[ \$- == *i* ]] && [[ -z \"\$($launched_var)\" ]]; then
  if command -v ($shell) >/dev/null 2>&1; then
    export ($launched_var)=1
    exec ($shell) || echo \"Failed to start ($shell)\"
  fi
fi
"

  if not ($rc_path | path exists) {
    error make {msg: $"($rc) not found"}
  }
  if not (open $rc_path | str contains $marker) {
    $snippet | save --append $rc_path
    log+ $"Added ($shell) auto-start to ($rc)"
  } else {
    log+ $"($shell) auto-start already in ($rc), skipping"
  }
}
