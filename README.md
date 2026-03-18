# Linux Setup for developers on PikaOS/Fedora/Ubuntu/Arch

Setup development workstation with [niri](https://mangowc.vercel.app) or [mangowc](https://mangowc.vercel.app) as your window manager.

```bash
bash -c "$(curl -sSL https://raw.githubusercontent.com/pervezfunctor/linux-config/refs/heads/main/setup)"
```

## Examples

Once the repo has been bootstrapped to `~/.local/share/linux-config`, you can use either:

- the root launcher: `~/.local/share/linux-config/setup.ts`
- the TypeScript CLI package under `~/.local/share/linux-config/ts/`
- Nushell helpers under `~/.local/share/linux-config/nu/`

For the TypeScript CLI, run commands from `~/.local/share/linux-config/ts`.

```bash
cd ~/.local/share/linux-config/ts

# Run the interactive shell setup
bun run setup shell

# Install shell tools only (pixi + brew)
bun run setup pixi-pkgs

# Clone/update dotfiles and apply Nushell + fish config
bun run setup dotfiles

# Run the interactive desktop setup
bun run setup desktop

# Install desktop apps from Flathub
bun run setup flatpaks

# Install and configure niri
bun run setup niri

# View the latest bootstrap log
bun run logs show

## Install IDEs

If you don't like `Zed` editor, you could install either VS Code and/or Antigravity using brew. Use the following instructions.

```bash
cd ~/.local/share/linux-config/ts
bun run setup brew
brew install --cask visual-studio-code-linux
brew install --cask antigravity-linux
```

## Install browsers.

There are three modern browsers avaialable on `flathub`: [LibreWolf](https://librewolf.net/), [Zen](https://zen-browser.app/) based on Firefox, and [Vivaldi](https://vivaldi.com/) based on Chromium. Use the following instructions to install any of them.

```bash
cd ~/.local/share/linux-config/ts
bun run setup flatpaks
fpi io.gitlab.librewolf-community
fpi app.zen_browser.zen
fpi com.vivaldi.Vivaldi
```
