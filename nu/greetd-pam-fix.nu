#!/usr/bin/env nu

def main [] {
  let pam_file = "/etc/pam.d/greetd"

  if not ($pam_file | path exists) {
    error make { msg: $"PAM file not found: ($pam_file)" }
  }

  let required_lines = [
    "auth     optional pam_gnome_keyring.so"
    "session  optional pam_gnome_keyring.so auto_start"
  ]

  let original = open $pam_file | lines
  let normalise = {|l| $l | str trim | str replace --regex '^-' ''}

  let lines = $required_lines | reduce --fold $original {|req, lines|
    let is_active    = ($lines | any {|l| ($l | str trim) == $req })
    let is_commented = not $is_active and ($lines | any {|l| (do $normalise $l) == $req })

    if $is_active {
      $lines
    } else if $is_commented {
      print $"Uncommented: ($req)"
      $lines | each {|l| if (do $normalise $l) == $req { $l | str trim | str replace --regex '^-' '' } else { $l }}
    } else {
      print $"Added: ($req)"
      $lines | append $req
    }
  }

  if $lines == $original {
    print "No changes needed."
    return
  }

  let backup = $"($pam_file).bak"
  cp $pam_file $backup

  $lines
    | str join (char newline)
    | sudo tee $pam_file
    | ignore

  print $"Updated ($pam_file)"
  print $"Backup written to ($backup)"
}
