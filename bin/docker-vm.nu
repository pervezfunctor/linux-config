#!/usr/bin/env nu

use incus-firewall-config.nu *

const VM_NAME = "docker"
const VM_CPUS = 4
const VM_MEM = "8GiB"
const VM_DISK = "30GiB"
const TIMEOUT = 120sec
const INTERVAL = 2sec
const TOTAL_CHECKS = 60

def show-progress [current: int, total: int] {
  let percent = (($current / $total) * 100 | into int)
  let bar_len = 20
  let filled = (($current * $bar_len) / $total | into int)
  let bar = ((1..$filled | each { "▓" } | str join) + (1..($bar_len - $filled) | each { "░" } | str join))
  print $"\rWaiting for VM... [($bar)] ($percent)%  " 
}

# Check VM connectivity (IPv4 first, then IPv6)
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

# Log an error message with red X
def log-error [message: string] {
  print $"(ansi red)✗ ($message)(ansi reset)"
}

# Check if incus is installed
def check-incus [] {
  if (which incus | is-empty) {
    log-error "incus is not installed"
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
  log "Creating VM..."
  ^incus launch images:debian/13 $VM_NAME --vm -c security.secureboot=false -c $"limits.cpu=($VM_CPUS)" -c $"limits.memory=($VM_MEM)" -d $"root,size=($VM_DISK)"
}

def start-vm-if-needed [] {
  let status = (get-vm-status)
  if $status != "RUNNING" {
    print $"VM is not running. Status: ($status). Starting..."
    ^incus start $VM_NAME
  } else {
    log "VM is already running."
  }
}

def install-docker [] {
  let user_name = ($env.USER? | default (whoami))
  let password = ($env.PASSWORD? | default $user_name)

  print "==> Installing Docker inside VM..."

  # Build the script to execute inside the VM
  let script = "
apt-get update
apt-get install -y ca-certificates curl

curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

systemctl enable --now docker
systemctl enable --now ssh

addgroup root docker || true

echo \"net.ipv4.ip_forward=1\" >> /etc/sysctl.d/99-ipforward.conf
sysctl -p /etc/sysctl.d/99-ipforward.conf || true

docker version
docker run --rm hello-world

if ! id \"$USER_NAME\" >/dev/null 2>&1; then
  useradd -m -s /bin/bash \"$USER_NAME\"
  echo \"$USER_NAME:$PASSWORD\" | chpasswd
fi

echo \"$USER_NAME ALL=(ALL) NOPASSWD:ALL\" > /etc/sudoers.d/$USER_NAME
addgroup \"$USER_NAME\" docker 2>/dev/null || true
"

  ^incus exec $VM_NAME -- env $"USER_NAME=($user_name)" $"PASSWORD=($password)" bash -eux $script

  print $"User '($user_name)' created with sudo permissions (password: '($password)')"
  print $"Connect as user: incus exec ($VM_NAME) -- su - ($user_name)"
  print $"Or via ssh: ssh ($user_name)@<vm-ip-address>"
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
    log-error "VM does not exist. Run without arguments to create it."
    exit 1
  }
  start-vm-if-needed
  wait-for-vm
  log "VM started and ready"
}

def cmd-stop [] {
  check-incus
  if not (vm-exists) {
    log-error "VM does not exist"
    exit 1
  }
  let status = (get-vm-status)
  if $status == "RUNNING" {
    log "Stopping VM..."
    ^incus stop $VM_NAME
    log "VM stopped"
  } else {
    log "VM is not running"
  }
}

def cmd-restart [] {
  check-incus
  if not (vm-exists) {
    log-error "VM does not exist. Run without arguments to create it."
    exit 1
  }
  log "Restarting VM..."
  ^incus restart $VM_NAME
  wait-for-vm
  log "VM restarted and ready"
}

def cmd-remove [] {
  check-incus
  if not (vm-exists) {
    log "VM does not exist"
    exit 0
  }
  let status = (get-vm-status)
  if $status == "RUNNING" {
    log "Stopping VM first..."
    ^incus stop $VM_NAME --force
  }
  log "Removing VM..."
  ^incus delete $VM_NAME
  log "VM removed"
}

def cmd-exec [...args: string] {
  check-incus
  if not (vm-exists) {
    log-error "VM does not exist"
    exit 1
  }
  let status = (get-vm-status)
  if $status != "RUNNING" {
    log-error "VM is not running. Start it first with: docker-vm.nu start"
    exit 1
  }
  let cmd_str = ($args | str join " ")
  if ($cmd_str | str trim | is-empty) {
    log "Opening shell in VM..."
    ^incus exec $VM_NAME -- bash
  } else {
    ^incus exec $VM_NAME -- bash -c $cmd_str
  }
}

def cmd-status [] {
  check-incus
  if not (vm-exists) {
    log-error "VM does not exist"
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
    log "VM has internet connectivity (IPv4)"
  } else {
    log-error "VM does NOT have internet connectivity (IPv4)"
  }
}

def main [
  command?: string     # Command: create, start, stop, restart, remove, exec, status (default: create)
  ...args: string      # Arguments for exec command
] {
  let cmd = ($command | default "create")
  match $cmd {
    "create" => { cmd-create }
    "start" => { cmd-start }
    "stop" => { cmd-stop }
    "restart" => { cmd-restart }
    "remove" => { cmd-remove }
    "exec" => { cmd-exec ...$args }
    "status" => { cmd-status }
    _ => {
      log-error $"Unknown command: ($cmd)"
      print "Usage: docker-vm.nu [create|start|stop|restart|remove|exec|status]"
      exit 1
    }
  }
}
