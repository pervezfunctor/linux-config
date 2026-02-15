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
    $ip = input $"(ansi blue)Enter Proxmox host IP address:(ansi reset) "

    if (is-valid-ip $ip) {
      $valid = true
    } else {
      print $"(ansi red)Invalid IP format. Use x.x.x.x format.(ansi reset)"
    }
  }

  $ip
}

def prompt-identity []: nothing -> string {
  mut identity = ""
  mut valid = false

  while not $valid {
    let prompt = $"(ansi yellow)Enter identity file \(optional, press Enter to skip\):(ansi reset) "
    $identity = input $prompt

    if $identity == "" {
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

def get-ssh-cmd [username: string, ip: string, identity: string]: nothing -> record {
  {
    username: $username
    ip: $ip
    identity: $identity
  }
}

def run-ssh [conn: record, command: string]: nothing -> record<exit_code: int, stdout: string, stderr: string> {
  let ssh_args = if $conn.identity != "" {
    ["-i", $conn.identity, $"($conn.username)@($conn.ip)", $command]
  } else {
    [$"($conn.username)@($conn.ip)", $command]
  }

  try {
    ssh ...$ssh_args | complete
  } catch {
    {exit_code: 1, stdout: "", stderr: "Connection failed"}
  }
}

def parse-guest-line [line: string, guest_type: string]: nothing -> record {
  let parts = $line | split row " " | where {|p| $p != ""}

  if ($parts | length) < 2 {
    return {}
  }

  let vmid = $parts | get 0
  let name = $parts | get 1
  let status = if ($parts | length) >= 3 { $parts | get 2 } else { "unknown" }

  {
    vmid: $vmid
    name: $name
    type: $guest_type
    status: $status
  }
}

def get-vms [conn: record]: nothing -> list<record> {
  mut vms = []

  let vms_raw = run-ssh $conn "qm list --full 2>/dev/null || qm list"

  if $vms_raw.exit_code == 0 and $vms_raw.stdout != "" {
    let vm_lines = $vms_raw.stdout | lines | skip 1
    for line in $vm_lines {
      if $line != "" {
        let guest = parse-guest-line $line "vm"
        if ($guest | is-not-empty) {
          $vms = $vms | append $guest
        }
      }
    }
  }

  $vms
}

def get-containers [conn: record]: nothing -> list<record> {
  mut containers = []

  let containers_raw = run-ssh $conn "pct list"

  if $containers_raw.exit_code == 0 and $containers_raw.stdout != "" {
    let ct_lines = $containers_raw.stdout | lines | skip 1
    for line in $ct_lines {
      if $line != "" {
        let guest = parse-guest-line $line "container"
        if ($guest | is-not-empty) {
          $containers = $containers | append $guest
        }
      }
    }
  }

  $containers
}

def discover-guests [conn: record]: nothing -> list<record> {
  print $"(ansi cyan)Discovering VMs and containers...(ansi reset)"

  let vms = get-vms $conn
  let containers = get-containers $conn

  $vms | append $containers
}

def get-container-ip [conn: record, vmid: string]: nothing -> string {
  let result = run-ssh $conn $"pct exec ($vmid) -- ip -4 addr show scope global | grep inet"
  if $result.exit_code == 0 and $result.stdout != "" {
    let inet_line = $result.stdout | lines | first
    let parts = $inet_line | split row " "
    let addr_with_cidr = $parts | get 1
    $addr_with_cidr | split row "/" | get 0
  } else {
    ""
  }
}

def get-vm-ip [conn: record, vmid: string]: nothing -> string {
  let result = run-ssh $conn $"qm guest exec ($vmid) -- ip -4 addr show scope global"
  if $result.exit_code == 0 and $result.stdout != "" {
    let inet_lines = $result.stdout | lines | where {|l| $l =~ "inet "}
    if ($inet_lines | length) > 0 {
      let inet_line = $inet_lines | first
      let parts = $inet_line | split row " "
      let inet_idx = ($parts | enumerate | where {|p| $p.item == "inet"} | first).index
      let addr_with_cidr = $parts | get ($inet_idx + 1)
      $addr_with_cidr | split row "/" | get 0
    } else {
      ""
    }
  } else {
    ""
  }
}

def get-guest-ip [conn: record, vmid: string, guest_type: string]: nothing -> string {
  if $guest_type == "container" {
    get-container-ip $conn $vmid
  } else {
    get-vm-ip $conn $vmid
  }
}

def select-guests [guests: list<record>]: nothing -> list<record> {
  if ($guests | length) == 0 {
    print $"(ansi red)No guests found.(ansi reset)"
    return []
  }

  # Separate VMs and containers
  let vms = $guests | where {|g| $g.type == "vm"}
  let containers = $guests | where {|g| $g.type == "container"}

  mut selected_guests = []

  # Display and select VMs
  if ($vms | length) > 0 {
    print $"\n(ansi magenta)=== Virtual Machines ===(ansi reset)"
    print $"(ansi yellow)Index  VMID    Status      Name(ansi reset)"
    print "──────────────────────────────────────────────"

    for vm in ($vms | enumerate) {
      let idx = $vm.index
      let v = $vm.item
      let status_color = if $v.status == "running" { "green" } else { "red" }
      print $"($idx | fill -a l -c ' ' -w 3)    ($v.vmid | fill -a l -c ' ' -w 6) (ansi $status_color)($v.status | fill -a l -c ' ' -w 10)(ansi reset) ($v.name)"
    }

    print $"\n(ansi cyan)Select VMs by index \(comma-separated, e.g., 0,2\) or 'all' or 'none':(ansi reset) "
    let vm_selection = input "VM Selection: "

    if $vm_selection == "all" {
      $selected_guests = $selected_guests | append $vms
    } else if $vm_selection != "none" and $vm_selection != "" {
      let indices = $vm_selection | split row "," | each {|s| $s | str trim | into int }
      let selected_vms = $vms | enumerate | where {|g| $g.index in $indices } | get item
      $selected_guests = $selected_guests | append $selected_vms
    }
  }

  # Display and select Containers
  if ($containers | length) > 0 {
    print $"\n(ansi blue)=== Containers ===(ansi reset)"
    print $"(ansi yellow)Index  CTID    Status      Name(ansi reset)"
    print "──────────────────────────────────────────────"

    for ct in ($containers | enumerate) {
      let idx = $ct.index
      let c = $ct.item
      let status_color = if $c.status == "running" { "green" } else { "red" }
      print $"($idx | fill -a l -c ' ' -w 3)    ($c.vmid | fill -a l -c ' ' -w 6) (ansi $status_color)($c.status | fill -a l -c ' ' -w 10)(ansi reset) ($c.name)"
    }

    print $"\n(ansi cyan)Select Containers by index \(comma-separated, e.g., 0,2\) or 'all' or 'none':(ansi reset) "
    let ct_selection = input "Container Selection: "

    if $ct_selection == "all" {
      $selected_guests = $selected_guests | append $containers
    } else if $ct_selection != "none" and $ct_selection != "" {
      let indices = $ct_selection | split row "," | each {|s| $s | str trim | into int }
      let selected_cts = $containers | enumerate | where {|g| $g.index in $indices } | get item
      $selected_guests = $selected_guests | append $selected_cts
    }
  }

  $selected_guests
}

def test-connection [conn: record]: nothing -> bool {
  print $"(ansi yellow)Testing connection to Proxmox host...(ansi reset)"

  let test_result = run-ssh $conn "echo 'Connection successful'"

  if $test_result.exit_code != 0 {
    print $"(ansi red)Failed to connect to Proxmox host. Check your credentials and network.(ansi reset)"
    if $test_result.stderr != "" {
      print $"Error: ($test_result.stderr)"
    }
    return false
  }

  print $"(ansi green)✓ Connected to Proxmox host(ansi reset)"
  true
}

def build-server-record [guest: record, ip: string, username: string, identity: string]: nothing -> record {
  # Build base record with common fields
  let base = {
    name: $guest.name
    type: $guest.type
    ip: $ip
    username: $username
    identity: $identity
  }

  # Add type-specific fields for readability
  if $guest.type == "vm" {
    $base | merge {
      vmid: $guest.vmid
      vm_name: $guest.name
    }
  } else {
    $base | merge {
      ctid: $guest.vmid
      ct_name: $guest.name
    }
  }
}

def get-guest-credentials [guest_name: string, default_user: string, default_identity: string]: nothing -> record {
  let use_defaults = input $"  Use default credentials for ($guest_name)? \(y/n, default: y\): " | default "y"

  if ($use_defaults | str downcase) == "y" {
    {username: $default_user, identity: $default_identity}
  } else {
    let user = prompt-username $default_user
    let ident = prompt-identity
    {username: $user, identity: $ident}
  }
}

def start-guest [conn: record, guest: record]: nothing -> bool {
  let cmd = if $guest.type == "vm" {
    $"qm start ($guest.vmid)"
  } else {
    $"pct start ($guest.vmid)"
  }

  print $"  (ansi yellow)Starting ($guest.name)...(ansi reset)"
  let result = run-ssh $conn $cmd

  if $result.exit_code == 0 {
    print $"  (ansi green)✓ Started ($guest.name)(ansi reset)"
    # Wait a moment for the guest to initialize
    sleep 5sec
    true
  } else {
    print $"  (ansi red)✗ Failed to start ($guest.name)(ansi reset)"
    if $result.stderr != "" {
      print $"  Error: ($result.stderr)"
    }
    false
  }
}

def process-guest [guest: record, conn: record, default_user: string, default_identity: string]: nothing -> record {
  # Check if guest is running, offer to start if not
  if $guest.status != "running" {
    print $"(ansi yellow)($guest.name) ($guest.type) is not running \(status: ($guest.status)\)(ansi reset)"
    let start_it = input $"  Start it? \(y/n, default: y\): " | default "y"

    if ($start_it | str downcase) == "y" {
      if not (start-guest $conn $guest) {
        return {}
      }
    } else {
      print $"  (ansi yellow)Skipping ($guest.name)(ansi reset)"
      return {}
    }
  }

  print $"(ansi yellow)Getting IP for ($guest.name) ($guest.type) ...(ansi reset)"

  let guest_ip = get-guest-ip $conn $guest.vmid $guest.type

  if $guest_ip != "" {
    print $"  (ansi green)✓ Found IP: ($guest_ip)(ansi reset)"
    let creds = get-guest-credentials $guest.name $default_user $default_identity
    build-server-record $guest $guest_ip $creds.username $creds.identity
  } else {
    print $"  (ansi red)✗ Could not determine IP for ($guest.name)(ansi reset)"
    let manual_ip = input $"  Enter IP manually \(or press Enter to skip\): "

    if $manual_ip != "" {
      let creds = get-guest-credentials $guest.name $default_user $default_identity
      build-server-record $guest $manual_ip $creds.username $creds.identity
    } else {
      {}
    }
  }
}

def process-selected-guests [selected: list<record>, conn: record, default_user: string, default_identity: string]: nothing -> list<record> {
  print $"\n(ansi cyan)--- Discovering Guest IPs ---(ansi reset)"
  print "(ansi yellow)Note: This may take a moment for each guest...(ansi reset)\n"

  mut servers = []

  for guest in $selected {
    let server = process-guest $guest $conn $default_user $default_identity
    if ($server | is-not-empty) {
      $servers = $servers | append $server
    }
  }

  $servers
}

def save-config [servers: list<record>, defaults: record, output: path]: nothing -> bool {
  if ($servers | length) == 0 {
    print $"(ansi red)No servers configured.(ansi reset)"
    return false
  }

  let output_data = {
    defaults: $defaults
    servers: $servers
  }

  $output_data | to json | save -f $output
  true
}

def print-summary [servers: list<record>, output: path] {
  print $"\n(ansi green)=== Configuration Complete ===(ansi reset)"
  print $"Saved ($servers | length) servers to (ansi cyan)($output)(ansi reset)"

  # Separate VMs and containers for summary
  let vms = $servers | where {|s| $s.type == "vm"}
  let containers = $servers | where {|s| $s.type == "container"}

  if ($vms | length) > 0 {
    print $"\n(ansi magenta)Virtual Machines:(ansi reset)"
    for vm in $vms {
      print $"  • VMID ($vm.vmid): ($vm.vm_name) \(($vm.ip)\)"
    }
  }

  if ($containers | length) > 0 {
    print $"\n(ansi blue)Containers:(ansi reset)"
    for ct in $containers {
      print $"  • CTID ($ct.ctid): ($ct.ct_name) \(($ct.ip)\)"
    }
  }
}

def get-proxmox-connection [ip: string, username: string, identity: string]: nothing -> record {
  let proxmox_ip = if $ip != "" and (is-valid-ip $ip) {
    $ip
  } else {
    prompt-ip
  }

  let proxmox_user = if $username != "" {
    $username
  } else {
    prompt-username "root"
  }

  let proxmox_identity = if $identity != "" {
    $identity
  } else {
    prompt-identity
  }

  {
    ip: $proxmox_ip
    username: $proxmox_user
    identity: $proxmox_identity
  }
}

def get-guest-defaults [guest_username: string, guest_identity: string]: nothing -> record {
  let default_guest_user = if $guest_username != "" {
    $guest_username
  } else {
    input $"(ansi green)Default username for guests \(press Enter for 'root'\):(ansi reset) " | default "root"
  }

  let default_guest_identity = if $guest_identity != "" {
    $guest_identity
  } else {
    prompt-identity
  }

  {
    username: $default_guest_user
    identity: $default_guest_identity
  }
}

def main [
  ip: string = ""
  --output: path = "servers.json"
  --username: string = ""
  --identity: string = ""
  --guest-username: string = ""
  --guest-identity: string = ""
] {
  print "(ansi cyan)=== Proxmox Guest Discovery ===(ansi reset)\n"

  let conn = get-proxmox-connection $ip $username $identity

  if not (test-connection $conn) {
    return
  }

  let guests = discover-guests $conn

  if ($guests | length) == 0 {
    print $"(ansi red)No VMs or containers found on this Proxmox host.(ansi reset)"
    return
  }

  print $"(ansi green)Found ($guests | length) guests(ansi reset)"

  let selected = select-guests $guests

  if ($selected | length) == 0 {
    print $"(ansi red)No guests selected.(ansi reset)"
    return
  }

  print $"\n(ansi cyan)--- Guest Configuration ---(ansi reset)"

  let guest_defaults = get-guest-defaults $guest_username $guest_identity
  let servers = process-selected-guests $selected $conn $guest_defaults.username $guest_defaults.identity

  let defaults = {
    username: $guest_defaults.username
    identity: $guest_defaults.identity
  }

  if (save-config $servers $defaults $output) {
    print-summary $servers $output
  }
}
