#!/usr/bin/env nu

# Docker VM management script for Incus
# Creates and configures an Alpine Linux VM with Docker installed

# VM configuration
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

# Check if VM exists
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

# Create the VM
def create-vm [] {
  log "Creating VM..."
  ^incus launch images:alpine/edge $VM_NAME --vm -c security.secureboot=false -c $"limits.cpu=($VM_CPUS)" -c $"limits.memory=($VM_MEM)" -d $"root,size=($VM_DISK)"
}

# Start the VM if not running
def start-vm-if-needed [] {
  let status = (get-vm-status)
  if $status != "RUNNING" {
    print $"VM is not running (status: ($status)). Starting..."
    ^incus start $VM_NAME
  } else {
    log "VM is already running."
  }
}

# Wait for VM to become ready
def wait-for-vm [] {
  print "==> Waiting for VM to become ready..."
  mut elapsed = 0sec

  while $elapsed < $TIMEOUT {
    let result = (do -i {
      ^incus exec $VM_NAME -- sh -c "ping -c1 1.1.1.1 >/dev/null 2>&1"
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

# Install Docker and configure the VM
def install-docker [] {
  let user_name = ($env.USER? | default (whoami))
  let password = ($env.PASSWORD? | default $user_name)

  print "==> Installing Docker inside VM..."

  # Build the script to execute inside the VM
  let script = "
apk update

apk add --no-cache \\
  docker \\
  docker-cli \\
  docker-openrc \\
  ca-certificates \\
  curl \\
  bash \\
  git \\
  doas \\
  openssh-server

rc-update add docker boot
rc-service docker start

sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/#PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config

rc-update add sshd default
rc-service sshd start

addgroup root docker || true

echo \"net.ipv4.ip_forward=1\" >> /etc/sysctl.conf
sysctl -p || true

docker version
docker run --rm hello-world

if ! id \"$USER_NAME\" >/dev/null 2>&1; then
  adduser -D -s /bin/bash \"$USER_NAME\"
  echo \"$USER_NAME:$PASSWORD\" | chpasswd
fi

echo \"permit nopass $USER_NAME as root\" > /etc/doas.d/doas.conf
addgroup \"$USER_NAME\" docker 2>/dev/null || true
"

  # Execute the script with environment variables
  ^incus exec $VM_NAME -- env $"USER_NAME=($user_name)" $"PASSWORD=($password)" sh -eux $script

  print $"User '($user_name)' created with doas permissions (password: '($password)')"
  print $"Connect as user: incus exec ($VM_NAME) -- su - ($user_name)"
  print $"Or via ssh: ssh ($user_name)@<vm-ip-address>"
  print $"Get VM IP with: incus list ($VM_NAME) --format csv --columns 4"
}

# Main entry point
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
