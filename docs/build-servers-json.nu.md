# build-servers-json.nu

An interactive Nushell script to manually build a `servers.json` configuration file by prompting for server details one by one. Useful when you don't have Proxmox access but need to create a server inventory.

**Usage:**
```
nu bin/build-servers-json.nu [output_file]
```

**Arguments:**
- `output_file` - Path to save the JSON file (default: `servers.json`)

**Interactive Prompts:**
1. Set default username and identity file (optional)
2. For each server:
   - Username (can use default or specify new)
   - IP address (validated for proper format)
   - Identity file (optional, can use default)
3. Option to add more servers

**Features:**
- Validates IP addresses (x.x.x.x format, 0-255 per octet)
- Verifies identity files exist before accepting
- Allows per-server override of defaults
- Generates properly formatted `servers.json`

**Examples:**
```bash
nu bin/build-servers-json.nu                    # Create servers.json interactively
nu bin/build-servers-json.nu my-servers.json    # Save to custom filename
```
