#!/usr/bin/env nu

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
