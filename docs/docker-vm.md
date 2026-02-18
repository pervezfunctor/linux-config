# Docker VM

A Nushell-based tool for managing a Docker VM using [Incus](https://linuxcontainers.org/incus/). Creates a Debian VM with Docker pre-installed.

## Requirements

- Incus installed and configured
- sudo access (for firewall configuration)

## Usage

```bash
~/.local/share/linux-config/bin/docker-vm.nu [command]
```

## Commands

| Command | Description |
|---------|-------------|
| `create` | Create and start the VM with Docker (default) |
| `start` | Start the existing VM |
| `stop` | Stop the running VM |
| `restart` | Restart the VM |
| `remove` | Remove the VM completely |
| `exec` | Execute commands inside the VM |
| `status` | Show VM status and connectivity info |

## Examples

```bash
# Create VM with Docker
docker-vm.nu create

# Start the VM
docker-vm.nu start

# Check status
docker-vm.nu status

# Execute commands inside VM
docker-vm.nu exec docker ps
docker-vm.nu exec bash

# Stop the VM
docker-vm.nu stop

# Remove the VM
docker-vm.nu remove
```

## VM Configuration

- **Name**: docker
- **OS**: Debian 13
- **CPUs**: 4
- **Memory**: 8GiB
- **Disk**: 30GiB

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `USER` | Username to create in VM | Current user |
| `PASSWORD` | Password for user | Same as username |

The created user has sudo permissions without password.

## Connecting to the VM

```bash
# Via incus exec
incus exec docker -- su - <username>

# Via SSH (if SSH server is running)
ssh <username>@<vm-ip>
```

Get VM IP with:
```bash
incus list docker --format csv --columns 4
```
