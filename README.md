# Linux Setup for developers on PikaOS/Fedora/Ubuntu/Arch

Setup development workstation with [niri](https://mangowm.vercel.app) or [mangowm](https://mangowm.vercel.app) as your window manager.

Open terminal and execute the following command. This is an interactive script.

```bash
bash -c "$(curl -sSL https://raw.githubusercontent.com/pervezfunctor/linux-config/refs/heads/main/setup)"
```

## Examples

Once the repo has been bootstrapped to `~/.linux-config`, you can run the setup scripts directly.

```bash
# Run the interactive shell setup
nu setup-shell.nu

# Run the interactive desktop setup
nu setup-desktop.nu
```

## Install IDEs

If you don't like `Zed` editor, you could install either VS Code and/or Antigravity using brew. Use the following instructions.

```bash
nu ~/.linux-config/nu/setup-shell.nu brew
brew install --cask visual-studio-code-linux
brew install --cask antigravity-linux
```

## Install browsers.

There are three modern browsers avaialable on `flathub`: [LibreWolf](https://librewolf.net/), [Zen](https://zen-browser.app/) based on Firefox, and [Vivaldi](https://vivaldi.com/) based on Chromium. Use the following instructions to install any of them.

```bash
fpi io.gitlab.librewolf-community
fpi app.zen_browser.zen
fpi com.vivaldi.Vivaldi
```

## Install additional shell packages

Many shell applications are available `conda` and they can be easily installed with `pixi`. For example

```bash
p ansible lazydocker
```

If not available in `conda`, then you could try `brew`.

```bash
b opencode codex
```
