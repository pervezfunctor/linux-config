#!/usr/bin/env nu

use ./lib.nu *

def "main help" [] {
  print "shell-autostart.nu - Auto-start a shell from another shell's rc file"
  print ""
  print "Usage:"
  print "  nu shell-autostart.nu <shell> <rc>"
  print "  nu shell-autostart.nu help"
  print ""
  print "Arguments:"
  print "  shell   Shell to start (e.g. fish, zsh)"
  print "  rc      RC file to inject into (e.g. .bashrc, .bash_profile)"
  print ""
  print "Example:"
  print "  nu shell-autostart.nu fish .bashrc"
}

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
