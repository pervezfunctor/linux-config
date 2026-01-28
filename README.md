## Niri Setup for developers on PikaOS/Fedora

Use the following script and what you need. You MUST select at least system packages on first run. You could run the script multiple times to select different options.

```bash
bash -c "$(curl -sSL https://raw.githubusercontent.com/pervezfunctor/niri-config/refs/heads/master/scripts/setup)"
```

If you need docker run the following script to install docker inside a VM and use `devpod` for development.

```bash
~/.local/share/chezmoi/scripts/docker-vm
```

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

For development environment conside mise, it's simple and effecient. You could also use nix.

For desktop apps, try flatpak first. If `Bazaar` is installed you could use it to install apps. Or

```bash
flatpak install --user flathub <package>
```
