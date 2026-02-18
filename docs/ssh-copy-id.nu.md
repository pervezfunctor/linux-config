# ssh-copy-id.nu

A Nushell script that copies SSH public keys to multiple servers defined in a `servers.json` file. Checks for existing SSH keys and offers to generate one if missing.

**Usage:**
```
nu bin/ssh-copy-id.nu [json_file]
```

**Arguments:**
- `json_file` - Path to servers JSON file (default: `bin/servers.json`)

**Features:**
- Checks for default SSH keys (`id_ed25519.pub`, `id_rsa.pub`)
- Offers to generate an ed25519 key if none found
- Supports custom identity files per-server or via defaults
- Colorized output showing success/failure per server
- Validates that usernames are provided for each server

**Examples:**
```bash
nu bin/ssh-copy-id.nu                           # Use default bin/servers.json
nu bin/ssh-copy-id.nu ~/my-servers.json         # Use custom servers file
```
