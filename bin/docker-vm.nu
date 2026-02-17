#!/usr/bin/env nu

const VM_NAME = "docker"
const VM_CPUS = 4
const VM_MEM = "8GiB"
const VM_DISK = "30GiB"
const TIMEOUT = 120sec
const INTERVAL = 2sec

# Log a message with green arrow
def log [message: string] {
  print $"(ansi green)→ ($message)(ansi reset)"
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
    print $"VM is not running (status: ($status)). Starting..."
    ^incus start $VM_NAME
  } else {
    log "VM is already running."
  }
}

def wait-for-vm [] {
  print "==> Waiting for VM to become ready..."
  mut elapsed = 0sec

  while $elapsed < $TIMEOUT {
    let result = (do -i {
      ^incus exec $VM_NAME -- bash -c "ping -c1 1.1.1.1 >/dev/null 2>&1"
    } | complete)

    if $result.exit_code == 0 {
      log "VM is ready!"
      return
    }

    sleep $INTERVAL
    $elapsed = $elapsed + $INTERVAL
    print $"Waiting... (($elapsed)/($TIMEOUT))"
  }

  log-error $"VM failed to become ready within ($TIMEOUT)"
  error make {
    msg: $"VM failed to become ready within ($TIMEOUT)"
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

def main [] {
  print "==> Checking Incus..."
  check-incus

  if not (vm-exists) {
    create-vm
  } else {
    print "VM already exists."
    start-vm-if-needed
  }

  wait-for-vm
  install-docker
}
