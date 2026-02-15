#!/usr/bin/env nu

def update [] {
  sudo dnf update -y
}

def firmware [] {
  sudo dnf install fwupdmgr -y
  sudo fwupdmgr get-devices
  sudo fwupdmgr refresh --force
  sudo fwupdmgr get-updates
  sudo fwupdmgr update
}

def set-hostname [] {
  let hostname = input "Enter hostname: "
  if ($hostname | is-empty) {
    print "Hostname cannot be empty"
    set-hostname
  } else {
    sudo hostnamectl set-hostname $hostname
  }
}

def flathub [] {
  flatpak remote-delete fedora
  flatpak remote-add --if-not-exists --subset=verified flathub https://flathub.org/repo/flathub.flatpakrepo
}

def nvidia [] {
  sudo dnf install -y kernel-devel kernel-headers gcc make dkms acpid libglvnd-glx libglvnd-opengl libglvnd-devel pkgconfig
  let fedora_ver = (rpm -E %fedora)
  sudo dnf install -y $"https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-($fedora_ver).noarch.rpm"
  sudo dnf install -y $"https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-($fedora_ver).noarch.rpm"
  sudo dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda

  sudo journalctl -f -u akmods
  nvidia-smi
}

def rebuild-nvidia-drivers [] {
  let kernel = (^uname -r)
  sudo akmods --kernels $kernel --rebuild
}

def amd [] {
  sudo dnf install -y mesa-va-drivers-freeworld mesa-vdpau-drivers-freeworld
}

def intel [] {
  sudo dnf install -y intel-media-driver
}

def codecs [] {
  sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing

  sudo dnf install -y gstreamer1-plugins-bad-* gstreamer1-plugins-good-* gstreamer1-plugins-base \
    gstreamer1-plugin-openh264 gstreamer1-libav lame* \
    --exclude=gstreamer1-plugins-bad-free-devel

  sudo dnf group install -y multimedia
  sudo dnf group install -y sound-and-video

  sudo dnf install -y openh264 gstreamer1-plugin-openh264 mozilla-openh264

  sudo dnf config-manager --set-enabled fedora-cisco-openh264
  sudo dnf update -y
}

def compress [] {
  sudo dnf install -y p7zip p7zip-plugins unrar
}

def utc [] {
  sudo timedatectl set-local-rtc 0 --adjust-system-clock
}

def appimage [] {
  sudo dnf install -y fuse fuse-libs
  flatpak --user install -y flathub it.mijorus.gearlever
}

def fonts [] {
  sudo dnf install -y curl cabextract xorg-x11-font-utils fontconfig
  print "WARNING: Installing unsigned Microsoft Core Fonts from SourceForge."
  sudo rpm -i --nodigest --nosignature https://downloads.sourceforge.net/project/mscorefonts2/rpms/msttcore-fonts-installer-2.6-1.noarch.rpm
}

def network [] {
  sudo systemctl disable NetworkManager-wait-online.service

  sudo dnf install -y dnsconfd
  sudo systemctl enable --now dnsconfd
  sudo systemctl disable --now systemd-resolved
  sudo systemctl mask systemd-resolved
  sudo mkdir -p /etc/NetworkManager/conf.d
  let config = "[main]
dns=dnsconfd

[global-dns]
resolve-mode=exclusive

[global-dns-domain-*]
servers=dns+tls://1.1.1.1#one.one.one.one
"
  $config | sudo tee /etc/NetworkManager/conf.d/global-dot.conf | ignore

  sudo systemctl restart NetworkManager
}

def btrfs [] {
  sudo dnf install -y btrfs-assistant btrbk snapper
  sudo systemctl enable --now snapper-timeline.timer
  sudo systemctl enable --now snapper-cleanup.timer
}

def deja-dup [] {
  sudo dnf install -y deja-dup
  flatpak install -y flathub org.gnome.DejaDup
}

def steam [] {
  sudo dnf install -y steam
  sudo dnf install -y mangohud
}

def flatpak-steam [] {
  sudo dnf remove -y steam
  flatpak install -y flathub com.valvesoftware.Steam
}

def brave [] {
  sudo dnf install -y dnf-plugins-core
  sudo dnf config-manager --add-repo https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
  sudo rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
  sudo dnf install -y brave-browser
}

def librewolf [] {
  curl -fsSL https://repo.librewolf.net/librewolf.repo | sudo tee /etc/yum.repos.d/librewolf.repo | ignore
  sudo dnf install -y librewolf
}

def vscode [] {
  sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
  let repo_content = "[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
"
  $repo_content | sudo tee /etc/yum.repos.d/vscode.repo | ignore
  sudo dnf install -y code
}

def multimedia [] {
  flatpak install -y flathub com.obsproject.Studio
  flatpak install -y flathub org.audacityteam.Audacity
}

def gnome [] {
  sudo rm /etc/xdg/autostart/org.gnome.Software.desktop
  sudo dnf install -y gnome-tweaks
  sudo dnf install -y gnome-themes-extra
  flatpak install -y flathub com.mattjakeman.ExtensionManager
}

def cleanup [] {
  sudo dnf clean all
  sudo dnf autoremove -y
}

def select-tasks [] {
  let tasks = [
    {name: "update", description: "Update packages", handler: { update }}
    {name: "flathub", description: "Setup flathub", handler: { flathub }}
    {name: "firmware", description: "Update firmware", handler: { firmware }}
    {name: "appimage", description: "Setup appimage support", handler: { appimage }}
    {name: "nvidia", description: "Install nvidia drivers", handler: { nvidia }}
    {name: "rebuild-nvidia-drivers", description: "Rebuild nvidia drivers", handler: { rebuild-nvidia-drivers }}
    {name: "amd", description: "Install AMD drivers", handler: { amd }}
    {name: "intel", description: "Install Intel drivers", handler: { intel }}
    {name: "set-hostname", description: "Set hostname", handler: { set-hostname }}
    {name: "codecs", description: "Install codecs", handler: { codecs }}
    {name: "compress", description: "Setup zip tools", handler: { compress }}
    {name: "utc", description: "Setup time", handler: { utc }}
    {name: "fonts", description: "Setup fonts", handler: { fonts }}
    {name: "network", description: "Setup network", handler: { network }}
    {name: "btrfs", description: "Setup btrfs", handler: { btrfs }}
    {name: "deja-dup", description: "Install deja-dup", handler: { deja-dup }}
    {name: "steam", description: "Install steam", handler: { steam }}
    {name: "flatpak-steam", description: "Install steam flatpak", handler: { flatpak-steam }}
    {name: "brave", description: "Install brave", handler: { brave }}
    {name: "librewolf", description: "Install librewolf", handler: { librewolf }}
    {name: "vscode", description: "Install vscode", handler: { vscode }}
    {name: "multimedia", description: "Install multimedia tools", handler: { multimedia }}
    {name: "gnome", description: "Setup gnome", handler: { gnome }}
    {name: "cleanup", description: "Cleanup", handler: { cleanup }}
  ]

  print "Select tasks to execute:"

  $tasks | input list --multi --display description
}

def main [] {
  let tasks = select-tasks

  if ($tasks | is-empty) {
    print "No tasks selected."
    return
  }

  for task in $tasks {
    print $"Executing: ($task.name)"
    do $task.handler
  }
}
