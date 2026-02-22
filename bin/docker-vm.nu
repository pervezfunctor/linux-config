#!/usr/bin/env nu

use incus-firewall-config.nu *
use ../nu/logs.nu [log+ warn+ error+ die]

const VM_NAME = "docker"
const VM_CPUS = 4
const VM_MEM = "8GiB"
const VM_DISK = "30GiB"
const TIMEOUT = 120sec
const INTERVAL = 2sec
const TOTAL_CHECKS = 60

def show-progress [current: int, total: int] {
  let percent = (($current * 100) / $total | into int)
  let bar_len = 20
  let filled = (($current * $bar_len) / $total | into int)
  let empty_count = $bar_len - $filled
  let bar_filled = if $filled > 0 { (1..$filled | each { |_| "▓" } | str join) } else { "" }
  let bar_empty = if $empty_count > 0 { (1..$empty_count | each { |_| "░" } | str join) } else { "" }
  let bar = $bar_filled + $bar_empty
  print $"\rWaiting for VM... [($bar)] ($percent)%  "
}

def check-vm-connectivity [] {
  let result_v4 = (do -i { ^incus exec $VM_NAME -- bash -c "ping -c1 -W 2 1.1.1.1 >/dev/null 2>&1" } | complete)
  if $result_v4.exit_code == 0 {
    return {ready: true, ip: "IPv4"}
  }

  let result_v6 = (do -i { ^incus exec $VM_NAME -- bash -c "ping -c1 -W 2 2606:4700:4700::1111 >/dev/null 2>&1" } | complete)
  if $result_v6.exit_code == 0 {
    return {ready: true, ip: "IPv6"}
  }

  {ready: false, ip: ""}
}

def wait-for-vm [] {
  print "==> Waiting for VM to become ready..."

  mut ready = false
  mut ip_type = ""
  mut check = 0

  while $check < $TOTAL_CHECKS and not $ready {
    show-progress $check $TOTAL_CHECKS
    let result = check-vm-connectivity
    if $result.ready {
      $ready = true
      $ip_type = $result.ip
    } else {
      sleep $INTERVAL
      $check = $check + 1
    }
  }
}

def print-error [message: string] {
  error+ $message
}


def check-incus [] {
  if (which incus | is-empty) {
    print-error "incus is not installed"
    print $"(ansi green)→ Please install incus first(ansi reset)"
    error make {
      msg: "incus is not installed"
    }
  }
}

def vm-exists []: nothing -> bool {
  let result = (do -i { ^incus info $VM_NAME } | complete)
  $result.exit_code == 0
}

# Get VM status
def get-vm-status []: nothing -> string {
  let result = (do -i { ^incus list $VM_NAME --format csv --columns s } | complete)
  if $result.exit_code == 0 {
    $result.stdout | str trim
  } else {
    ""
  }
}

def create-vm [] {
  print "Creating VM..."
  ^incus launch images:debian/13 $VM_NAME --vm -c security.secureboot=false -c $"limits.cpu=($VM_CPUS)" -c $"limits.memory=($VM_MEM)" -d $"root,size=($VM_DISK)"
}

def start-vm-if-needed [] {
  let status = (get-vm-status)
  if $status != "RUNNING" {
    print $"VM is not running. Status: ($status). Starting..."
    ^incus start $VM_NAME
  } else {
    print "VM is already running."
  }
}

def install-docker [] {
  let user_name = ($env.USER? | default (whoami))
  let password = ($env.PASSWORD? | default $user_name)

  print "==> Installing Docker inside VM..."

  let script_dir = ($env.CURRENT_FILE | path dirname | path join .. bin)
  let script_path = ($script_dir | path join install-docker-vm.sh)
  if not ($script_path | path exists) {
    error make {
      msg: $"Script not found: ($script_path)"
    }
  }

  ^incus file push $script_path $"($VM_NAME)/tmp/install-docker.sh"
  try {
    ^incus exec $VM_NAME -- bash /tmp/install-docker.sh $user_name $password
  } catch {
    print $"Docker installation failed: ($in)"
  }
  ^incus exec $VM_NAME -- rm /tmp/install-docker.sh

  print $"User '($user_name)' created with sudo permissions"

  print $"Connect as user: incus exec ($VM_NAME) -- su - ($user_name)"
  print $"Or via ssh: ssh ($user_name)@<vm-ip-address>"
  print $"Password if asked: ($password)"
  print $"Get VM IP with: incus list ($VM_NAME) --format csv --columns 4"
}

def cmd-create [] {
  print "==> Checking Incus..."
  check-incus

  print "==> Checking firewall configuration..."
  configure-incus-firewall

  if not (vm-exists) {
    create-vm
  } else {
    print "VM already exists."
    start-vm-if-needed
  }

  wait-for-vm
  install-docker
}

def cmd-start [] {
  check-incus
  if not (vm-exists) {
    print-error "VM does not exist. Run without arguments to create it."
    exit 1
  }
  start-vm-if-needed
  wait-for-vm
  print "VM started and ready"
}

def cmd-stop [] {
  check-incus
  if not (vm-exists) {
    print-error "VM does not exist"
    exit 1
  }
  let status = (get-vm-status)
  if $status == "RUNNING" {
    print "Stopping VM..."
    ^incus stop $VM_NAME
    print "VM stopped"
  } else {
    print "VM is not running"
  }
}

def cmd-restart [] {
  check-incus
  if not (vm-exists) {
    print-error "VM does not exist. Run without arguments to create it."
    exit 1
  }
  print "Restarting VM..."
  ^incus restart $VM_NAME
  wait-for-vm
  print "VM restarted and ready"
}

def cmd-remove [] {
  check-incus
  if not (vm-exists) {
    print "VM does not exist"
    exit 0
  }
  let status = (get-vm-status)
  if $status == "RUNNING" {
    print "Stopping VM first..."
    ^incus stop $VM_NAME --force
  }
  print "Removing VM..."
  ^incus delete $VM_NAME
  print "VM removed"
}

def cmd-exec [...args: string] {
  check-incus
  if not (vm-exists) {
    print-error "VM does not exist"
    exit 1
  }
  let status = (get-vm-status)
  if $status != "RUNNING" {
    print-error "VM is not running. Start it first with: docker-vm.nu start"
    exit 1
  }
  let cmd_str = ($args | str join " ")
  if ($cmd_str | str trim | is-empty) {
    print "Opening shell in VM..."
    ^incus exec $VM_NAME -- bash
  } else {
    ^incus exec $VM_NAME -- bash -c $cmd_str
  }
}

def cmd-shell [] {
  check-incus
  if not (vm-exists) {
    print-error "VM does not exist"
    exit 1
  }
  let status = (get-vm-status)
  if $status != "RUNNING" {
    print-error "VM is not running. Start it first with: docker-vm.nu start"
    exit 1
  }
  let user_name = ($env.USER? | default (whoami))
  print $"Opening shell as user '($user_name)'..."
  ^incus exec $VM_NAME -- su - $user_name
}

def cmd-status [] {
  check-incus
  if not (vm-exists) {
    print-error "VM does not exist"
    exit 1
  }

  print "==> VM Status:"
  ^incus list $VM_NAME --format table

  print "\n==> VM Network:"
  ^incus exec $VM_NAME -- ip addr

  print "\n==> Host iptables FORWARD chain:"
  do -i { ^sudo iptables -L FORWARD -v -n }

  print "\n==> Host iptables DOCKER-USER chain:"
  do -i { ^sudo iptables -L DOCKER-USER -v -n }

  print "\n==> Testing VM connectivity:"
  let ping_test = (do -i { ^incus exec $VM_NAME -- bash -c "ping -c1 -W 3 1.1.1.1" } | complete)
  if $ping_test.exit_code == 0 {
    print "VM has internet connectivity (IPv4)"
  } else {
    print-error "VM does NOT have internet connectivity (IPv4)"
  }
}

def cmd-help [] {
  print ("
docker-vm.nu - Manage Docker VM with Incus

Usage: docker-vm.nu [command]

Commands:
  create    Create and start the VM with Docker
  start     Start the existing VM
  stop      Stop the running VM
  restart   Restart the VM
  remove    Remove the VM completely
  shell     Open shell as the user (not root)
  exec      Execute commands inside the VM
  status    Show VM status and connectivity info
  help      Show this help message

Examples:
  docker-vm.nu create
  docker-vm.nu create --password mysecret
  docker-vm.nu start
  docker-vm.nu shell
  docker-vm.nu exec docker ps
  docker-vm.nu status

Options:
  --password    Password for user (default: same as username)

Environment:
  USER    Username to create in VM (default: current user)
" | str trim)
}

def main [
  command?: string     # Command: create, start, stop, restart, remove, shell, exec, status, help (default: create)
  --password: string  # Password for user (default: same as username)
  ...args: string     # Arguments for exec command
] {
  $env.PASSWORD = $password

  let cmd = ($command | default "help")
  match $cmd {
    "create" => { cmd-create }
    "start" => { cmd-start }
    "stop" => { cmd-stop }
    "restart" => { cmd-restart }
    "remove" => { cmd-remove }
    "shell" => { cmd-shell }
    "exec" => { cmd-exec ...$args }
    "status" => { cmd-status }
    "help" => { cmd-help }
    _ => {
      print-error $"Unknown command: ($cmd)"
      print "Usage: docker-vm.nu [create|start|stop|restart|remove|shell|exec|status|help]"
      exit 1
    }
  }
}
