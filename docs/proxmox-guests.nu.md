# proxmox-guests.nu

An interactive Nushell script for discovering Proxmox VMs and containers, then generating a `servers.json` configuration file for SSH access. Connects to a Proxmox host, lists all guests, and helps configure SSH credentials for each selected guest.

**Usage:**
```
nu bin/proxmox-guests.nu [ip] [--output <file>] [--username <user>] [--identity <file>] [--guest-username <user>] [--guest-identity <file>]
```

**Arguments:**
- `ip` - Proxmox host IP address (optional, will prompt if not provided)
- `--output`, `-o` - Output file path (default: `servers.json`)
- `--username` - Username for Proxmox host connection (default: prompts, suggests `root`)
- `--identity` - SSH identity file for Proxmox host (optional)
- `--guest-username` - Default username for discovered guests (default: prompts, suggests `root`)
- `--guest-identity` - Default SSH identity for guests (optional)

**Features:**
- Discovers both VMs (via `qm list`) and containers (via `pct list`)
- Interactive guest selection with visual status indicators
- Automatically retrieves guest IP addresses via `qm guest exec` or `pct exec`
- Prompts for credentials per-guest or uses defaults
- Can start stopped guests before configuring
- Generates a `servers.json` file compatible with other tools in this repo

**Examples:**
```bash
nu bin/proxmox-guests.nu                      # Interactive mode
nu bin/proxmox-guests.nu 192.168.1.100        # Connect to specific Proxmox host
nu bin/proxmox-guests.nu --output cluster.json --guest-username admin
```

**Output Format:**
The generated JSON follows the `servers.json` schema with guest metadata:
```json
{
  "defaults": {"username": "root", "identity": "~/.ssh/id_ed25519"},
  "servers": [
    {"name": "web-server", "type": "vm", "vmid": "100", "ip": "10.0.0.5", "username": "root"},
    {"name": "db-container", "type": "container", "ctid": "200", "ip": "10.0.0.6", "username": "admin"}
  ]
}
```
