#!/usr/bin/env nu

def has-default-ssh-key []: nothing -> bool {
  let ssh_dir = $nu.home-path | path join ".ssh"
  let default_keys = ["id_ed25519.pub", "id_rsa.pub"]

  for key in $default_keys {
    let key_path = $ssh_dir | path join $key
    if ($key_path | path exists) {
      return true
    }
  }
  false
}

def prompt-generate-key []: nothing -> bool {
  print $"(ansi yellow)No SSH key found.(ansi reset)"
  print "Would you like to generate an ed25519 SSH key?"

  let response = input "Generate SSH key? [y/N]: "
  $response | str downcase | str trim | $in == "y" or $in == "yes"
}

def generate-ssh-key []: nothing -> nothing {
  print $"(ansi cyan)Generating ed25519 SSH key...(ansi reset)"
  let result = ssh-keygen -t ed25519 -C $"($nu.env.USER)@($nu.hostname)" | complete

  if $result.exit_code == 0 {
    print $"(ansi green)✓ SSH key generated successfully(ansi reset)"
  } else {
    print $"(ansi red)✗ Failed to generate SSH key(ansi reset)"
    if $result.stderr != "" { print $"  Error: ($result.stderr)" }
  }
}

def copy-key [host: string, identity: string] {
  let result = if $identity != "" {
    print $"  Using identity file: ($identity)"
    ssh-copy-id -i $identity $host | complete
  } else {
    print "  Using default SSH key"
    ssh-copy-id $host | complete
  }

  if $result.exit_code == 0 {
    print $"(ansi green)✓ Successfully copied SSH key to ($host)(ansi reset)"
  } else {
    print $"(ansi red)✗ Failed to copy SSH key to ($host)(ansi reset)"
    if $result.stderr != "" { print $"  Error: ($result.stderr)" }
  }
}

def main [json_file: path = "bin/servers.json"] {
  let data = open $json_file

  let uses_default = ($data.servers | any { |s|
    ($s.identity? | is-empty) and ($data.defaults.identity? | is-empty)
  })

  if $uses_default and (not (has-default-ssh-key)) {
    if (prompt-generate-key) {
      generate-ssh-key
    } else {
      print $"(ansi red)No SSH key available. Exiting.(ansi reset)"
      return
    }
  }

  print $"(ansi cyan)--- Starting SSH Key Copy ---(ansi reset)"
  print $"Processing ($data.servers | length) servers..."

  for server in $data.servers {
    let username = $server.username? | default ($data.defaults.username? | default "")
    if $username == "" {
      print $"(ansi red)No username provided for server ($server.ip)(ansi reset)"
      continue
    }

    let identity = $server.identity? | default ($data.defaults.identity? | default "")
    let host = $"($username)@($server.ip)"

    print $"\n(ansi yellow)Copying SSH key to ($host)...(ansi reset)"
    copy-key $host $identity
  }

  print $"\n(ansi cyan)--- SSH Key Copy Complete ---(ansi reset)"
}

