# Setup

## Initial Setup

Use the following script and select what you need. You MUST select at least system packages and dotfiles on the first run. You could run this script multiple times to select different options.

```bash
bash -c "$(curl -sSL https://raw.githubusercontent.com/pervezfunctor/linux-config/refs/heads/master/bin/bootstrap)" -- all
```

## Docker VM

If you need docker run the following script to install docker inside a VM and use `devpod` for development. See [docs/docker-vm.md](docker-vm.md) for detailed documentation.

```bash
~/.local/share/linux-config/bin/docker-vm
```

## Package Installation

If you wish to install additional packages, first see if you operating system package manager has it. For eg.

```bash
# On PikaOS
pikman install <package>

# On Fedora
sudo dnf install <package>

# On Debian/Ubuntu
sudo apt install <package>
```

If the package is not available in your operating system package manager, you could try installing it with `pixi` or `brew`. For eg.

```bash
# With pixi
pixi global install <package>

# With brew
brew install <package>
```

For development environment consider mise, it's simple and efficient. You could also use nix.

For desktop apps, try flatpak first. If `Bazaar` is installed you could use it to install apps. Or

```bash
flatpak install --user flathub <package>
```

You can also install `nix` with above script, and use `home-manager` to manage your system. You need to modify nix files to add/remove packages.
