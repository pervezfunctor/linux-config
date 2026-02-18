# Distroboxes

This repository includes a Nushell-based tool for managing distroboxes (see [distrobox](https://github.com/89luca89/distrobox) for more info).

```bash
~/.local/share/linux-config/bin/distroboxes.nu --help
```

## Available Commands

| Command | Description |
|---------|-------------|
| `create-all` | Create all distroboxes (default) |
| `list` | List existing distroboxes |
| `start-all` | Start all tmuxp distroboxes |
| `stop-all` | Stop all tmuxp distroboxes |
| `restart-all` | Restart all tmuxp distroboxes |
| `exec-all` | Execute a command in all tmuxp distroboxes |
| `enter` | Enter a specific distrobox |
| `enter-all` | Enter all tmuxp distroboxes sequentially |
| `remove-all` | Remove all tmuxp distroboxes |

## Distroboxes Created

- ubuntu-tmuxp
- debian-tmuxp
- fedora-tmuxp
- arch-tmuxp
- tumbleweed-tmuxp
- alpine-tmuxp

Each distrobox uses a custom home directory in `~/.boxes/<name>` to keep container files separate from your host home.

Note: All commands (except `enter`, `list`) operate only on boxes ending with `-tmuxp`.
