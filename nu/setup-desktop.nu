#!/usr/bin/env nu

use ./lib.nu *

def wm-install [] {
  mut pkgs = [
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
    "udiskie"
    "udisks2"
    "wireplumber"
    "wl-clipboard"
    "xdg-desktop-portal-gnome"
    "xdg-desktop-portal-gtk"
    "xdg-desktop-portal-wlr"
  ]
  if (is-apt ) {
    $pkgs = $pkgs ++ [
      "bibata-cursor-theme"
      "cliphist"
      "gvfs-backends"
      "gvfs-fuse"
      "libsecret-tools"
    ]
  }
  if (is-fedora) {
    $pkgs = $pkgs ++ [
      "adw-gtk3-theme"
      "cups-pk-helper"
      "gvfs-fuse"
      "gvfs-smb"
      "libsecret"
      # "power-profiles-daemon"
    ]
  }
  if (is-tw) {
    $pkgs = $pkgs ++ [
      "cliphist"
      "git-credential-libsecret"
      "gtk3-metatheme-adwaita"
      "gvfs-backend-samba"
      "gvfs-fuse"
      "libsecret-1-0"
      "pipewire-pulseaudio"
    ]
  }
  if (is-arch) {
    $pkgs = $pkgs ++ [
      "adw-gtk-theme"
      "cava"
      "cliphist"
      "cups-pk-helper"
      "gvfs-smb"
      "kimageformats"
      "libsecret"
      "matugen"
    ]
  }
  si $pkgs

  if (is-arch) {
    paru-install
    ^paru -S bibata-cursor-theme
  }

  main fonts

  if (has-cmd pipx) {
    log+ "Installing pywal packages"
    ^pipx install pywal
    ^pipx install pywalfox
  }

  let pictures = ($env.HOME | path join "Pictures")
  do -i { mkdir $"($pictures)/Screenshots" }
  do -i { mkdir $"($pictures)/Wallpapers" }

  stow-package "systemd"
  stow-package "kitty"
  stow-package "xdg"

  # xdg-mime default org.gnome.Nautilus.desktop inode/directory`
  # xdg-mime default firefox.desktop x-scheme-handler/http
  # xdg-mime default firefox.desktop x-scheme-handler/https
  # xdg-mime default org.pwmt.zathura.desktop application/pdf
  # xdg-mime default org.gnome.Loupe.desktop image/png
  # xdg-mime default org.gnome.Loupe.desktop image/jpeg
  # xdg-mime default org.gnome.Loupe.desktop image/webp
}

def "main niri install" [] {
  wm-install

  if (has-cmd dms) and (has-cmd niri) {
    log+ "niri and dms are already installed"
    return
  }

  log+ "Installing niri"
  if (is-pikaos) {
    ^pikman install pika-niri-desktop-minimal pika-niri-settings dms kimageformat-plugins cups-pk-helper
  } else if (is-fedora) {
    ^sudo dnf copr enable avengemedia/dms
    si ["niri" "dms" "cliphist"]
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
    si ["niri" "dms-shell"]
  } else {
    error+ "OS not supported. Not installing niri."
    return
  }
}

def "main niri config" [] {
  if (is-cachy) and not (has-cmd niri) {
    error+ "Use the niri edition of CachyOS instead of this one."
    return
  }

  stow-package "niri"

  let niri_dms = ($env.HOME | path join ".config/niri/dms")
  touch-files $niri_dms ["alttab.kdl" "colors.kdl" "layout.kdl" "wpblur.kdl" "binds.kdl" "cursor.kdl" "outputs.kdl"]

  do -i { ^systemctl --user add-wants niri.service dms }
}

def "main niri" [] {
  main niri install
  main niri config
}

def "main mangowc install" [] {
  wm-install

  if (has-cmd dms) and (has-cmd mango) {
    log+ "mangowc and dms are already installed"
    return
  }

  log+ "Installing mangowc"
  if (is-pikaos) {
    ^pikman install mangowc
  } else if (is-arch) {
    ^paru -S mangowc-git dms-shell-bin
  } else if (is-fedora) {
    if (prompt-yn "need terra repository for installing mango. This is NOT stable. Still enable it?") {
      ^sudo dnf install --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' terra-release
      ^sudo dnf copr enable avengemedia/dms
      si ["mangowc" "dms"]
    }
  } else {
    error+ "Unsupported OS. Not installing mangowc."
    return
  }
}

def "main mangowc config" [] {
  stow-package "mango"
  stow-package "systemd"

  let mango_dms = ($env.HOME | path join ".config/mango/dms")
  touch-files $mango_dms ["alttab.conf" "colors.conf" "layout.conf" "wpblur.conf" "binds.conf" "cursor.conf" "outputs.conf"]
}

def "main mangowc" [] {
  main mangowc install
  main mangowc config
}

def "main flatpaks" [] {
  if not (has-cmd flatpak) {
    si ["flatpak"]
  }

  log+ "Adding flathub remote"
  ^flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo --user

  let flatpaks = [
    "com.github.tchx84.Flatseal"
    "md.obsidian.Obsidian"
    "org.gnome.Firmware"
    "org.gnome.Papers"
    "app.zen_browser.zen"
  ]

  log+ "Installing flatpaks..."
  for pkg in $flatpaks {
    log+ $"Installing ($pkg)"
    ignore-error {|| ^flatpak --user install -y flathub $pkg }
  }
}

def "main system" [] {
  update-packages

  mut pkgs = [
    "flatpak"
    "gnome-keyring"
    "plocate"
  ]

  log+ "Installing system packages"
  si $pkgs
}

def "main distrobox" [] {
    log+ "Installing distrobox"
    si ["podman" "distrobox"]
}

def "main fonts" [] {
  if not (has-cmd brew) {
    brew-install
  }
  if not (has-cmd brew) {
    error+ "brew not installed, cannot install fonts"
    return
  }

  ^brew install --cask font-jetbrains-mono-nerd-font font-fontawesome
}

def "main zed" [] {
  if not (has-cmd zed) {
    log+ "Installing zed"
    ^sh -c (http get https://zed.dev/install.sh)
  }

  main fonts
}

def "main virt config" [] {
  log+ "Setting up libvirt"

  for group in ["libvirt" "qemu" "libvirt-qemu" "kvm" "libvirtd"] {
    do -i { ^sudo usermod -aG $group $env.USER }
  }

  do -i { ^sudo systemctl enable --now libvirtd }
  do -i { ^sudo systemctl enable --now libvirtd.socket }
  do -i { ^sudo virsh net-autostart default }

  if (has-cmd authselect) {
    do -i { ^sudo authselect enable-feature with-libvirt }
  }
}

def "main virt install" [] {
  log+ "Installing virt-manager"

  if not (is-arch) {
    warn+ "OS other than arch is not tested for virt-manager"
  }

  mut packages = [
    "virt-install"
    "virt-manager"
    "virt-viewer"
  ]

  if (is-fedora) or (is-tw) {
    $packages ++= [
      "libvirt-nss"
    ]
  }
  if (is-fedora) or (is-arch) or (is-tw) {
    $packages ++= [
      "dnsmasq"
      "libvirt"
      "qemu-img"
      "qemu-tools"
      "swtpm"
    ]
  }
  if (is-tw) {
    $packages ++= [
      "qemu"
      "qemu-x86"
      "qemu-ui-gtk"
      "qemu-ui-opengl"
    ]
  }

  if (is-arch) {
    $packages ++= [
      "openbsd-netcat"
      "qemu-full"
      "qemu-hw-display-virtio-gpu"
      "qemu-hw-display-virtio-gpu-gl"
    ]
  }

  si $packages
}

def "main virt" [] {
  main virt install
  main virt config
}

def "main setup-desktop" [] {
  mut items: list<record<description: string, handler: closure>> = []

  if not (is-fedora-atomic) {
    $items = $items ++ [
      { description: "Install system packages(required)", handler: { main system } }
      { description: "Install distrobox", handler: { main distrobox } }
      { description: "Install virt-manager", handler: { main virt } }
    ]
  }

  $items = $items ++ [
    { description: "Install flatpaks", handler: { main flatpaks } }
    { description: "Install zed", handler: { main zed } }
  ]

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

  multi-task $items
}

def "main help" [] {
  print "setup-desktop.nu - Linux desktop setup script"
  print ""
  print "Usage:"
  print "  nu setup-desktop.nu"
  print "  nu setup-desktop.nu help"
  print "  nu setup-desktop.nu <command> [args]"
  print ""
  print "Commands:"
  print "  setup-desktop    Interactive desktop setup (same as running with no command)"
  print "  help             Show this help message"
  print ""
  print "  system           Install desktop system packages"
  print "  distrobox        Install distrobox"
  print "  flatpaks         Install flatpak applications"
  print "  zed              Install zed editor and fonts"
  print "  fonts            Install desktop fonts with Homebrew"
  print ""
  print "  virt             Install and configure virt-manager/libvirt"
  print "  virt install     Install virt-manager/libvirt packages"
  print "  virt config      Configure libvirt for the current user"
  print ""
  print "  niri             Install and configure niri WM"
  print "  niri install     Install niri and dms"
  print "  niri config      Apply niri config"
  print ""
  print "  mangowc          Install and configure mangowc WM"
  print "  mangowc install  Install mangowc and dms"
  print "  mangowc config   Apply mangowc config"
  print ""
  print "Supported Systems:"
  print "  - Fedora (standard and atomic)"
  print "  - Debian Trixie"
  print "  - Ubuntu Questing"
  print "  - openSUSE Tumbleweed"
  print "  - Arch Linux"
  print "  - CachyOS"
  print "  - PikaOS"
}

def main [] {
  let job_id = keep-sudo-alive

  if (is-mac) {
    die "desktop option is not available for mac"
  }

  bootstrap
  main setup-desktop

  stop-sudo-alive $job_id
}
