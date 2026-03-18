# Linux Setup for developers on PikaOS/Fedora/Ubuntu/Arch

Setup development workstation with [niri](https://mangowc.vercel.app) or [mangowc](https://mangowc.vercel.app) as your window manager.

```bash
bash -c "$(curl -sSL https://raw.githubusercontent.com/pervezfunctor/linux-config/refs/heads/main/setup)"
```

## Examples

Once the repo has been bootstrapped to `~/.local/share/linux-config`, you can run the setup scripts directly.

```bash
# Run the interactive shell setup
bun setup.ts shell

# Install shell tools only (pixi + brew)
bun setup.ts pixi-pkgs

# Clone/update dotfiles and apply Nushell + fish config
bun setup.ts dotfiles

# Run the interactive desktop setup
bun setup.ts desktop

# Install desktop apps from Flathub
bun setup.ts flatpaks

# Install and configure niri
bun setup.ts niri
```

## Install IDEs

If you don't like `Zed` editor, you could install either VS Code and/or Antigravity using brew. Use the following instructions.

```bash
bun setup.ts brew
brew install --cask visual-studio-code-linux
brew install --cask antigravity-linux
```

## Install browsers.

There are three modern browsers avaialable on `flathub`: [LibreWolf](https://librewolf.net/), [Zen](https://zen-browser.app/) based on Firefox, and [Vivaldi](https://vivaldi.com/) based on Chromium. Use the following instructions to install any of them.

```bash
bun setup.ts flatpaks
fpi io.gitlab.librewolf-community
fpi app.zen_browser.zen
fpi com.vivaldi.Vivaldi
```
