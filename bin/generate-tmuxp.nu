#!/usr/bin/env nu

def main [servers_file: path, output_file: path = "remote-servers.yaml"] {
  let config = open $servers_file
  let defaults = $config.defaults? | default {username: "", identity: ""}
  let servers = $config.servers? | default []

  let panes = $servers | each {|row|
    let username = $row.username? | default $defaults.username
    let identity = $row.identity? | default $defaults.identity

    let ssh_cmd = if $identity != "" {
      $"ssh -i ($identity) ($username)@($row.ip)"
    } else {
      $"ssh ($username)@($row.ip)"
    }
    {shell_command: [$ssh_cmd]}
  }

  {
    session_name: "remote-servers"
    windows: [{
      window_name: "servers"
      layout: "tiled"
      panes: $panes
    }]
  } | to yaml | save -f $output_file
}
