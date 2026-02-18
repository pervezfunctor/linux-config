# generate-tmuxp.nu

A Nushell script that converts a `servers.json` file into a tmuxp YAML configuration for opening multiple SSH sessions in a single tmux window with tiled panes.

**Usage:**
```
nu bin/generate-tmuxp.nu <servers_file> [output_file]
```

**Arguments:**
- `servers_file` - Path to the servers JSON file (required)
- `output_file` - Path for the output YAML file (default: `remote-servers.yaml`)

**Features:**
- Generates tmuxp-compatible YAML configuration
- Creates one pane per server with appropriate SSH command
- Supports custom identity files (`ssh -i`)
- Uses tiled layout for optimal pane distribution
- Session name is set to `remote-servers`

**Examples:**
```bash
nu bin/generate-tmuxp.nu servers.json                    # Generate remote-servers.yaml
nu bin/generate-tmuxp.nu servers.json cluster.yaml       # Custom output filename
```

**Using the Output:**
```bash
tmuxp load remote-servers.yaml    # Launch tmux session with all servers
```
