#!/usr/bin/env nu

use ../lib/logs.nu *
use ../lib/lib.nu *
use ../lib/setup-lib.nu *

def snapper-config [] {
  if (is-pikaos) {
    log+ "snapper config only supported on pikaos"
  }

  if not (has-cmd snapper) {
    warn+ "Snapper is not installed. Skipping setup."
    return
  }

  let result = (do -i { ^sudo snapper list-configs } | complete)
  if ($result.stdout =~ "/") {
    log+ "Snapper is already setup for /"
    return
  }

  log+ "Setting up snapper"
  do -i {
    ^sudo snapper create-config /
    ^sudo mkdir -p /var/lib/refind-btrfs
    ^sudo chmod 755 /var/lib/refind-btrfs
    ^sudo systemctl enable refind-btrfs --now
  }
}

def wm-install [] {
  mut pkgs = [
    "cliphist"
    "grim"
    "gvfs"
    "imv"
    "kitty"
    "mate-polkit"
    "mpv"
    "nautilus"
    "pipewire"
    "pipewire-pulse"
    "qt5ct"
    "qt6ct"
    "slurp"
    "wireplumber"
    "wl-clipboard"
    "xdg-desktop-portal-gnome"
    "xdg-desktop-portal-gtk"
    "xdg-desktop-portal-wlr"
  ]

  if (is-ubuntu) { $pkgs = $pkgs ++ ["bibata-cursor-theme"] }
  if (is-fedora) { $pkgs = $pkgs ++ ["gvfs-smb"] }
  if (is-tw) { $pkgs = $pkgs ++ ["pipewire-pulseaudio"] }
  if (is-arch) { $pkgs = $pkgs ++ ["pipewire-jack"] }

  si $pkgs

  if (is-arch) {
    paru-install
  }

  let pictures = ($env.HOME | path join "Pictures")
  do -i { mkdir $"($pictures)/Screenshots" }
  do -i { mkdir $"($pictures)/Wallpapers" }

  stow-package "systemd"
  stow-package "kitty"
}

def niri-install [] {
  wm-install

  if (has-cmd dms) and (has-cmd niri) {
    log+ "niri and dms are already installed"
    return
  }

  log+ "Installing niri"
  if (is-pikaos) {
    ^pikman install pika-niri-desktop-minimal pika-niri-settings dms
  } else if (is-fedora) {
    ^sudo dnf copr enable avengemedia/dms
    si ["niri" "dms"]
  } else if (is-questing) {
    ^sudo add-apt-repository ppa:avengemedia/danklinux
    ^sudo add-apt-repository ppa:avengemedia/dms
    ^sudo apt update
    si ["niri" "dms"]
  } else if (is-tw) {
    ^sudo zypper addrepo https://download.opensuse.org/repositories/home:/AvengeMedia:/dms/openSUSE_Tumbleweed/home:AvengeMedia:dms.repo
    ^sudo zypper refresh
    si ["niri" "dms"]
  } else if (is-arch) {
    paru-install
    ^paru -S niri dms-shell-bin
  } else {
    error+ "OS not supported. Not installing niri."
    return
  }
}

def niri-config [] {
  stow-package "niri"

  let niri_dms = ($env.HOME | path join ".config/niri/dms")
  touch-files $niri_dms ["alttab.kdl" "colors.kdl" "layout.kdl" "wpblur.kdl" "binds.kdl" "cursor.kdl" "outputs.kdl"]

  do -i { ^systemctl --user add-wants niri.service dms }
}

def "main niri" [] {
  niri-install
  niri-config
}

def mangowc-install [] {
  wm-install

  if (has-cmd dms) and (has-cmd mango) {
    log+ "mangowc and dms are already installed"
    return
  }

  log+ "Installing mangowc"
  if (is-pikaos) {
    ^pikman install mangowc
  } else if (is-arch) {
    paru-install
    ^paru -S mangowc-git dms-shell-bin
  } else if (is-fedora) {
    if (prompt-yn "need terra repository for installing mango. This is NOT stable. Still enable it?") {
      ^sudo dnf install --nogpgcheck --repofrompath $"terra,https://repos.fyralabs.com/terra$releasever" terra-release
      ^sudo dnf copr enable avengemedia/dms
      si ["mangowc" "dms"]
    }
  } else {
    error+ "Unsupported OS. Not installing mangowc."
    return
  }
}

def mangowc-config [] {
  stow-package "mango"
  stow-package "systemd"

  let mango_dms = ($env.HOME | path join ".config/mango/dms")
  touch-files $mango_dms ["alttab.conf" "colors.conf" "layout.conf" "wpblur.conf" "binds.conf" "cursor.conf" "outputs.conf"]
  do -i { ^systemctl --user add-wants wm-session.target dms }
}

def "main mangowc" [] {
  mangowc-install
  mangowc-config
}

def hypr-install [] {
  wm-install

  if (has-cmd dms) and (has-cmd hyprctl) {
    log+ "hyprland and dms are already installed"
    return
  }

  log+ "Installing hyprland"
  if (is-pikaos) {
    ^pikman install pika-hyprland-desktop-minimal pika-hyprland-settings dms
    ^pikman install hyprpolkitagent
  } else if (is-arch) {
    paru-install
    ^paru -S hyprland dms-shell-bin
  } else if (is-tw) {
    ^sudo zypper addrepo https://download.opensuse.org/repositories/home:/AvengeMedia:/dms/openSUSE_Tumbleweed/home:AvengeMedia:dms.repo
    ^sudo zypper refresh
    si ["hyprland" "dms" "hyprpolkitagent"]
  } else {
    error+ "Unsupported OS. Not installing hyprland."
    return
  }
}

def hypr-config [] {
  stow-package "hypr"

  let hypr_dms = ($env.HOME | path join ".config/hypr/dms")
  touch-files hypr_dms ["alttab" "colors" "layout" "wpblur" "binds" "cursor" "outputs"]
  do -i { ^systemctl --user add-wants hyprland-session.target dms }
  do -i { ^systemctl --user add-wants wm-session.target dms }
}

def "main hypr" [] {
  hypr-install
  hypr-config
}

def "main flatpaks" [] {
  if not (has-cmd flatpak) {
    si ["flatpak"]
  }

  log+ "Adding flathub remote"
  ^flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo --user

  let flatpaks = [
    "app.zen_browser.zen"
    "com.github.tchx84.Flatseal"
    "com.spotify.Client"
    "io.github.flattool.Ignition"
    "io.github.kolunmi.Bazaar"
    "md.obsidian.Obsidian"
    "org.gnome.Firmware"
    "org.gnome.Papers"
    "org.gnome.World.PikaBackup"
    "org.telegram.desktop"
    "sh.loft.devpod"
  ]

  log+ "Installing flatpaks..."
  for pkg in $flatpaks {
    log+ $"Installing ($pkg)"
    do -i { ^flatpak --user install -y flathub $pkg }
  }
}

def "main system" [] {
  update-packages

  mut pkgs = [
    "flatpak"
    "gnome-keyring"
    "pass"
    "plocate"
    "gvfs"
  ]

  if (is-tw) { $pkgs = $pkgs ++ ["gopass"] }
  if (is-apt) { $pkgs = $pkgs ++ ["libsecret-tools"] }
  if (is-pikaos) {
    $pkgs = $pkgs ++ ["snapper-gui" "pika-refind-btrfs-hooks" "refind-btrfs"]
  }
  if (is-fedora) { $pkgs = $pkgs ++ ["gvfs-smb"] }
  if (is-arch) { $pkgs = $pkgs ++ ["gvfs-smb"] }

  log+ "Installing system packages"
  si $pkgs

  if (is-pikaos) {
    snapper-config
  }

  if (has-cmd pipx) {
    log+ "Installing pywal packages"
    ^pipx install pywal pywalfox
  }
}

def "main distrobox" [] {
  log+ "Installing distrobox"
  si ["podman" "distrobox"]
}

def "main vscode install" [] {
  if not (has-cmd code) {
    if not (has-cmd brew) {
      brew-install
    }

    log+ "Installing vscode"
    ^brew tap ublue-os/tap
    ^brew install --cask font-jetbrains-mono-nerd-font font-fontawesome
    ^brew install --cask visual-studio-code-linux
  }
}

def "main vscode extensions" [] {
  let extensions = [
    "jdinhlife.gruvbox"
    "jnoortheen.nix-ide"
    "mads-hartmann.bash-ide-vscode"
    "TheNuProjectContributors.vscode-nushell-lang"
    "timonwong.shellcheck"
    "wayou.vscode-todo-highlight"
  ]

  log+ "Installing vscode extensions"
  for ext in $extensions {
    log+ $"Installing ($ext)"
    do -i { ^code --install-extension $ext }
  }
}

def "main vscode config" [] {
  stow-package "vscode"
}

def "main vscode" [] {
  main vscode install
  main vscode extensions
  main vscode config
}

def "main zed" [] {
  if not (has-cmd zed) {
    log+ "Installing zed"
    ^curl -f https://zed.dev/install.sh | ^sh
  }

  stow-package "zed"
}

def "main virt" [] {
  log+ "Installing virt-manager"
  let packages = ["virt-manager" "virt-install" "virt-viewer"]
  si $packages

  for group in ["libvirt" "qemu" "libvirt-qemu" "kvm" "libvirtd"] {
    do -i { ^sudo usermod -aG $group $env.USER }
  }

  if (has-cmd authselect) {
    do -i { ^sudo authselect enable-feature with-libvirt }
  }
}

def gnome-extensions-install [] {
  if not (has-cmd gext) {
    if not (has-cmd pipx) {
      warn+ "pipx not found, skipping gnome extensions"
      return
    }
    ^pipx install gnome-extensions-cli --system-site-packages
  }

  if not (has-cmd gext) {
    warn+ "gext not found, skipping gnome extensions"
    return
  }

  let extensions = [
    "paperwm@paperwm.github.com"
    "search-light@icedman.github.com"
    "switcher@landau.fi"
    "windowsNavigator@gnome-shell-extensions.gcampax.github.com"
  ]

  let optional = [
    "just-perfection-desktop@just-perfection"
    "blur-my-shell@aunetx"
    "extension-list@tu.berry"
    "AlphabeticalAppGrid@stuarthayhurst"
    "tilingshell@ferrarodomenico.com"
  ]

  for ext in $extensions {
    do -i { ^gext install $ext }
    do -i { ^gext enable $ext }
  }
  for ext in $optional {
    do -i { ^gext install $ext }
    do -i { ^gext disable $ext }
  }
}

def gnome-flatpaks-install [] {
  let flatpaks = [
    "com.mattjakeman.ExtensionManager"
    "org.gtk.Gtk3theme.adw-gtk3"
    "org.gtk.Gtk3theme.adw-gtk3-dark"
    "org.gnome.Logs"
    "io.github.swordpuffin.rewaita"
    "io.missioncenter.MissionCenter"
    "app.devsuite.Ptyxis"
  ]
  for pkg in $flatpaks {
    do -i { ^flatpak --user install -y flathub $pkg }
  }
}

def gnome-settings-install [] {
  ^gsettings set org.gnome.mutter experimental-features "['scale-monitor-framebuffer']"
  ^gsettings set org.gnome.desktop.input-sources xkb-options "['caps:ctrl_modifier']"

  ^gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark'
  ^gsettings set org.gnome.desktop.interface cursor-theme 'Bibata-Modern-Classic'
  ^gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'

  ^gsettings set org.gnome.desktop.interface gtk-key-theme "Emacs"
  ^gsettings set org.gnome.desktop.interface accent-color 'teal'

  ^gsettings set org.gnome.mutter dynamic-workspaces false
  ^gsettings set org.gnome.desktop.wm.preferences num-workspaces 4

  ^gsettings set org.gnome.desktop.interface monospace-font-name 'JetbrainsMono Nerd Font 11'

  ^gsettings set org.gnome.desktop.wm.preferences resize-with-right-button true
}

def gnome-keybindings-install [] {
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/close-window "['<Super>BackSpace', '<Super>q']"

  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/switch-right "['<Super>Right']"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/switch-left "['<Super>Left']"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/switch-up "['<Super>Up']"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/switch-down "['<Super>Down']"

  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/move-up "['<Shift><Super>Up']"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/move-down "['<Shift><Super>Down']"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/move-left "['<Shift><Super>Left']"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/move-right "['<Shift><Super>Right']"

  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/switch-up-workspace "['<Super>Page_Up', '<Super><Control>Left']"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/switch-down-workspace "['<Super>Page_Down', '<Super><Control>Right']"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/move-up-workspace "['<Shift><Super>Page_Up', '<Super><Control><Shift>Left']"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/move-down-workspace "['<Shift><Super>Page_Down', '<Super><Control><Shift>Right']"

  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/new-window "['<Super>n']"

  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/move-monitor-above "@as []"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/move-monitor-below "@as []"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/move-monitor-left "@as []"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/move-monitor-right "@as []"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/move-space-monitor-above "@as []"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/move-space-monitor-below "@as []"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/move-space-monitor-left "@as []"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/move-space-monitor-right "@as []"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/open-window-position-down "@as []"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/open-window-position-left "@as []"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/swap-monitor-above "@as []"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/swap-monitor-below "@as []"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/swap-monitor-left "@as []"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/swap-monitor-right "@as []"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/switch-monitor-above "@as []"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/switch-monitor-below "@as []"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/switch-monitor-left "@as []"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/switch-monitor-right "@as []"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/switch-next "@as []"
  ^dconf write /org/gnome/shell/extensions/paperwm/keybindings/switch-previous "@as []"
  ^dconf write /org/gnome/shell/extensions/paperwm/show-window-position-bar false

  ^dconf write /org/gnome/desktop/wm/keybindings/show-desktop "@as []"

  ^dconf write /org/gnome/shell/extensions/search-light/secondary-shortcut-search "['<Super>d']"
  ^dconf write /org/gnome/shell/extensions/search-light/primary-shortcut-search "['<Super>Space']"

  ^dconf write /org/gnome/shell/extensions/dash-to-dock/hot-keys false
  ^dconf write /org/gnome/desktop/wm/preferences/num-workspaces 4
  ^dconf write /org/gnome/desktop/wm/keybindings/switch-to-workspace-1 "['<Super>1']"
  ^dconf write /org/gnome/desktop/wm/keybindings/switch-to-workspace-2 "['<Super>2']"
  ^dconf write /org/gnome/desktop/wm/keybindings/switch-to-workspace-3 "['<Super>3']"
  ^dconf write /org/gnome/desktop/wm/keybindings/switch-to-workspace-4 "['<Super>4']"
  ^dconf write /org/gnome/desktop/wm/preferences/workspace-names "['1', '2', '3', '4']"

  ^dconf write /org/gnome/shell/extensions/paperwm/show-workspace-indicator false
  ^dconf write /org/gnome/shell/extensions/paperwm/show-window-position-bar false

  ^dconf write /org/gnome/shell/extensions/blur-my-shell/panel/blur "false"
}

def "main gnome" [] {
  do -i {
    gnome-extensions-install
    gnome-keybindings-install
    gnome-settings-install
    gnome-flatpaks-install
  }
}

def "main setup-desktop" [] {
  init-log-file
  bootstrap

  mut items: list<record<description: string, handler: closure>> = []

  if not (is-fedora-atomic) {
    $items = $items ++ [
      { description: "Install desktop system packages", handler: { main system } }
      { description: "Install distrobox", handler: { main distrobox } }
      { description: "Install virt-manager", handler: { main virt } }
    ]
  }

  $items = $items ++ [
    { description: "Install vscode", handler: { main vscode } }
    { description: "Install flatpaks", handler: { main flatpaks } }
    { description: "Install zed", handler: { main zed } }
  ]

  if (is-gnome) {
    $items = $items ++ [
      { description: "Configure gnome desktop", handler: { main gnome } }
    ]
  }

  if (is-fedora) or (is-questing) or (is-pikaos) or (is-tw) or (is-arch) {
    $items = $items ++ [
      { description: "Install niri", handler: { main niri } }
    ]
  }

  if (is-fedora) or (is-pikaos) or (is-arch) {
    $items = $items ++ [
      { description: "Install mangowc", handler: { main mangowc } }
    ]
  }

  if (is-pikaos) or (is-tw) or (is-arch) {
    $items = $items ++ [
      { description: "Install hyprland", handler: { main hypr } }
    ]
  }

  let selected = ($items | input list --multi --display description "Select desktop tasks to execute:")

  if ($selected | is-empty) {
    log+ "No tasks selected."
    return
  }

  for item in $selected {
    log+ $"Executing: ($item.description)"
    do $item.handler
  }
}

def "main help" [] {
  print "setup-desktop.nu - Cross-platform desktop setup script"
  print ""
  print "Usage: nu setup-desktop.nu <command>"
  print ""
  print "Commands:"
  print "  setup-desktop  Interactive desktop setup (WMs, flatpaks, apps)"
  print "  system         Install desktop system packages"
  print "  distrobox      Install distrobox"
  print "  virt          Install virt-manager"
  print "  vscode        Install vscode and extensions"
  print "  flatpaks      Install flatpak applications"
  print "  zed           Install zed editor"
  print "  niri          Install niri WM"
  print "  mangowc       Install mangowc WM"
  print "  hypr          Install hyprland WM"
  print "  gnome         Configure GNOME desktop with extensions"
  print "  help          Show this help message"
  print ""
  print "Supported Systems:"
  print "  - Fedora (standard and atomic)"
  print "  - Debian Trixie"
  print "  - Ubuntu Questing"
  print "  - openSUSE Tumbleweed"
  print "  - Arch Linux"
  print "  - PikaOS"
}

def main [] {
  if (is-mac) {
    die "desktop option is not available for mac"
  }

  bootstrap
  main setup-desktop
}
