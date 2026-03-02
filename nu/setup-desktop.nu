#!/usr/bin/env nu

use ./lib.nu *

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

  if (is-apt ) { $pkgs = $pkgs ++ ["bibata-cursor-theme"] }
  if (is-fedora) { $pkgs = $pkgs ++ ["gvfs-smb" "adw3-gtk-theme"] }
  if (is-tw) { $pkgs = $pkgs ++ ["pipewire-pulseaudio" "gtk3-metatheme-adwaita"] }
  if (is-arch) {
    $pkgs = $pkgs ++ [
      "adw-gtk-theme"
      "cava"
      "cups-pk-helper"
      "kimageformats"
      "matugen"
    ]
  }

  si $pkgs

  if (is-arch) {
    paru-install
    paru -S bibata-cursor-theme
  }

  let pictures = ($env.HOME | path join "Pictures")
  do -i { mkdir $"($pictures)/Screenshots" }
  do -i { mkdir $"($pictures)/Wallpapers" }

  stow-package "systemd"
  stow-package "kitty"

  main brew fonts
}

def "main niri install" [] {
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
    ^paru -S niri dms-shell-bin
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
      ^sudo dnf install --nogpgcheck --repofrompath $"terra,https://repos.fyralabs.com/terra$releasever" terra-release
      ^sudo dnf copr enable avengemedia/dms
      si ["mangowc" "dms"]
    }
  } else {
    error+ "Unsupported OS. Not installing mangowc."
  }
}

def "main mangowc config" [] {
  stow-package "mango"
  stow-package "systemd"

  let mango_dms = ($env.HOME | path join ".config/mango/dms")
  touch-files $mango_dms ["alttab.conf" "colors.conf" "layout.conf" "wpblur.conf" "binds.conf" "cursor.conf" "outputs.conf"]

  do -i { ^systemctl --user add-wants wm-session.target dms }
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
  if (is-fedora) { $pkgs = $pkgs ++ ["gvfs-smb"] }
  if (is-arch) { $pkgs = $pkgs ++ ["gvfs-smb"] }

  log+ "Installing system packages"
  si $pkgs

  if (has-cmd pipx) {
    log+ "Installing pywal packages"
    ^pipx install pywal pywalfox
  }
}

def "main distrobox" [] {
    log+ "Installing distrobox"
    si ["podman" "distrobox"]
}

def "main brew fonts" [] {
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

  main brew fonts
  stow-package "zed"
}

def "main virt config" [] {
  log+ "Setting up libvirt"

  do -i {
    for group in ["libvirt" "qemu" "libvirt-qemu" "kvm" "libvirtd"] {
      ^sudo usermod -aG $group $env.USER
    }

    ^sudo systemctl enable --now libvirtd
    ^systemctl enable --now libvirtd.socket
    ^sudo virsh net-autostart default
    if (has-cmd authselect) {
      ^sudo authselect enable-feature with-libvirt
    }
  }
}

def "main virt install" [] {
  log+ "Installing virt-manager"
  mut packages = [
    "virt-install"
    "virt-manager"
    "virt-viewer"
  ]

  if (is-fedora) or (is-arch) {
    $packages ++= [
      "dnsmasq"
      "libvirt"
      "qemu-img"
      "qemu-tools"
      "swtpm"
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
  init-log-file
  bootstrap

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
  print "  flatpaks      Install flatpak applications"
  print "  zed           Install zed editor"
  print "  niri          Install niri WM"
  print "  mangowc       Install mangowc WM"
  print "  help          Show this help message"
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
  if (is-mac) {
    die "desktop option is not available for mac"
  }

  bootstrap
  main setup-desktop
}
