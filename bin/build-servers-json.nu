#!/usr/bin/env nu

def is-valid-ip [ip: string]: nothing -> bool {
  let parts = $ip | split row "."

  if ($parts | length) != 4 {
    return false
  }

  $parts | all {|p|
    try {
      let num = $p | into int
      $num >= 0 and $num <= 255
    } catch {
      false
    }
  }
}

def prompt-ip []: nothing -> string {
  mut ip = ""
  mut valid = false

  while not $valid {
    $ip = input $"(ansi blue)Enter IP address:(ansi reset) "

    if (is-valid-ip $ip) {
      $valid = true
    } else {
      print $"(ansi red)Invalid IP format. Use x.x.x.x format.(ansi reset)"
    }
  }

  $ip
}

def prompt-identity [default: string]: nothing -> string {
  mut identity = ""
  mut valid = false

  while not $valid {
    let prompt = if $default != "" {
      $"(ansi yellow)Enter identity file \(default: ($default)\):(ansi reset) "
    } else {
      $"(ansi yellow)Enter identity file \(optional\):(ansi reset) "
    }
    $identity = input $prompt

    if $identity == "" {
      $identity = $default
      $valid = true
    } else if ($identity | path expand | path exists) {
      $valid = true
    } else {
      print $"(ansi red)File not found: ($identity)(ansi reset)"
    }
  }

  $identity
}

def prompt-username [default: string]: nothing -> string {
  mut username = ""
  mut valid = false

  while not $valid {
    let prompt = if $default != "" {
      $"(ansi green)Enter username \(default: ($default)\):(ansi reset) "
    } else {
      $"(ansi green)Enter username:(ansi reset) "
    }
    let input_val = input $prompt

    $username = if $input_val == "" { $default } else { $input_val }

    if $username != "" {
      $valid = true
    } else {
      print $"(ansi red)Username cannot be empty.(ansi reset)"
    }
  }

  $username
}

def main [output_file: path = "servers.json"] {
  print "(ansi cyan)--- Set Defaults ---(ansi reset)"
  let default_user = input $"(ansi green)Default username \(press Enter to skip\):(ansi reset) "
  let default_identity = prompt-identity ""

  let defaults = {
    username: $default_user
    identity: $default_identity
  }

  print "\n(ansi cyan)--- Add Servers ---(ansi reset)"
  mut servers = []
  mut add_more = true

  while $add_more {
    let username = prompt-username $default_user

    let ip = prompt-ip
    let identity = prompt-identity $default_identity

    $servers = $servers | append {
      username: $username
      ip: $ip
      identity: $identity
    }

    let continue = input $"\n(ansi cyan)Add another server? \(y/n\):(ansi reset) "
    $add_more = ($continue | str downcase) == "y"
  }

  {
    defaults: $defaults
    servers: $servers
  } | to json | save -f $output_file

  print $"Saved ($servers | length) servers to ($output_file)"
}
