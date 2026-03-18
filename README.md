# Linux Setup for developers on PikaOS/Fedora/Ubuntu/Arch

Setup development workstation with [niri](https://mangowc.vercel.app) or [mangowc](https://mangowc.vercel.app) as your window manager.

```bash
bash -c "$(curl -sSL https://raw.githubusercontent.com/pervezfunctor/linux-config/refs/heads/main/setup)"
```

## Examples

Once the repo has been bootstrapped to `~/.local/share/linux-config`, you can run the setup scripts directly.

```bash
# Run the interactive shell setup
nu setup-shell.nu

# Install shell tools only
nu setup-shell.nu shell

# Clone/update dotfiles and apply Nushell + fish config
nu setup-shell.nu dotfiles

# Run the interactive desktop setup
nu setup-desktop.nu

# Install desktop apps from Flathub
nu setup-desktop.nu flatpaks

# Install and configure niri
nu setup-desktop.nu niri
```

## Install IDEs

If you don't like `Zed` editor, you could install either VS Code and/or Antigravity using brew. Use the following instructions.

```bash
nu ~/.local/share/linux-config/nu/setup-shell.nu brew
brew install --cask visual-studio-code-linux
brew install --cask antigravity-linux
```

## Install browsers.

There are three modern browsers avaialable on `flathub`: [LibreWolf](https://librewolf.net/), [Zen](https://zen-browser.app/) based on Firefox, and [Vivaldi](https://vivaldi.com/) based on Chromium. Use the following instructions to install any of them.

```bash
nu ~/.local/share/linux-config/nu/setup-desktop.nu flatpaks
fpi io.gitlab.librewolf-community
fpi app.zen_browser.zen
fpi com.vivaldi.Vivaldi
```
