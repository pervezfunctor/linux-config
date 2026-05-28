#!/usr/bin/env nu

use std/log
use ./lib.nu *

def "main vicinae" [] {
  if not (has-cmd gext) {
    error+ "Cannot install vicinae extension, gext not available"
    return
  }

  if not (has-cmd vicinae) {
    curl -fsSL https://vicinae.com/install | bash
  }
  do -i { systemctl --user enable --now vicinae }

  gext install vicinae@dagimg-dot
  gext enable vicinae@dagimg-dot

  dconf write /org/gnome/shell/extensions/paperwm/winprops "['{\"wm_class\":\"vicinae\",\"scratch_layer\":true}']"
  gnome-shortcut.nu create "App Launcher" -c "vicinae toggle" -s "<Super>d"
}

def "main extensions" [] {
  if not (has-cmd gext) {
    pipx install gnome-extensions-cli --system-site-packages
  }

  if not (has-cmd gext) {
    error+ "gext not found, skipping gnome extensions"
    return
  }

  let extensions = [
    "paperwm@paperwm.github.com"
    "switcher@landau.fi"
    "windowsNavigator@gnome-shell-extensions.gcampax.github.com"
    "blur-my-shell@aunetx"
    "user-theme@gnome-shell-extensions.gcampax.github.com"
  ]

  for ext in $extensions {
    do -i { gext install $ext }
    do -i { gext enable $ext }
  }
}

def "main flatpaks" [] {
  if not (has-cmd flatpak) {
    error+ "flatpak not found, skipping gnome flatpaks"
    return
  }

  log+ "Adding flathub remote"
  flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo --user

  let flatpaks = [
    "com.mattjakeman.ExtensionManager"
    "io.github.swordpuffin.rewaita"
    "org.gtk.Gtk3theme.adw-gtk3"
    "org.gtk.Gtk3theme.adw-gtk3-dark"
    "page.tesk.Refine"
    "dev.qwery.AddWater" # for firefox dark theme
  ]
  for pkg in $flatpaks {
    do -i { flatpak --user install -y flathub $pkg }
  }

  do -i {
    flatpak --user override --filesystem=xdg-config/gtk-3.0:rw
    flatpak --user override --filesystem=xdg-config/gtk-4.0:rw
  }
}

def "rewaita config" [] {
  '{
"light-theme": "Catppuccin Latte \ud83c\udf3b.css",
"dark-theme": "Catppuccin Mocha \ud83c\udf3f.css",
"window-controls": "colored",
"modify-gtk3-theme": true,
"modify-gnome-shell": true,
"run-in-background": true,
"firefox-theme": true,
"transparency": true,
"window": false,
"sharp": false,
"light-text": false
  }' | save -f ~/.var/app/io.github.swordpuffin.rewaita/data/prefs.json

  dconf write /org/gnome/shell/extensions/user-theme/name "'rewaita'"
}

def "main settings" [] {
  if not (has-cmd gsettings) {
    error+ "gsettings not found, skipping gnome settings"
    return
  }

  gsettings set org.gnome.desktop.input-sources xkb-options "['caps:ctrl_modifier']"
  gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
  gsettings set org.gnome.desktop.interface accent-color 'blue'
  gsettings set org.gnome.desktop.interface gtk-key-theme "Emacs"
  gsettings set org.gnome.desktop.wm.preferences resize-with-right-button true

  gsettings set org.gnome.mutter dynamic-workspaces false
  gsettings set org.gnome.desktop.wm.preferences num-workspaces 4

  if (is-cachy) {
    gsettings set org.gnome.desktop.background picture-uri "file:///usr/share/backgrounds/archlinux/archwave.png"
    gsettings set org.gnome.desktop.background picture-uri-dark "file:///usr/share/backgrounds/archlinux/archwave.png"
    gsettings set org.gnome.desktop.screensaver picture-uri "file:///usr/share/backgrounds/archlinux/archwave.png"
  } else if (is-resolute) {
    gsettings set org.gnome.desktop.background picture-uri "file:///usr/share/backgrounds/vale1ntin0omf-Electric_Veins_of_the_Storm.jpg"
    gsettings set org.gnome.desktop.background picture-uri-dark "file:///usr/share/backgrounds/vale1ntin0omf-Electric_Veins_of_the_Storm.jpg"
    gsettings set org.gnome.desktop.screensaver picture-uri "file:///usr/share/backgrounds/vale1ntin0omf-Electric_Veins_of_the_Storm.jpg"
  }

  if not (has-cmd dconf) {
    error+ "dconf not found, skipping gnome settings"
    return
  }

  do -i {
    dconf write /org/gnome/shell/extensions/blur-my-shell/panel/blur false
    dconf write /org/gnome/shell/extensions/blur-my-shell/applications/blur true
    dconf write /org/gnome/shell/extensions/blur-my-shell/applications/whitelist "['org.gnome.Ptyxis', 'dev.zed.Zed']"

    dconf write /org/gnome/shell/extensions/switcher/max-width-percentage "uint32 25"
    dconf write /org/gnome/shell/extensions/switcher/font-size "uint32 16"
    dconf write /org/gnome/shell/extensions/switcher/icon-size "uint32 16"
    dconf write /org/gnome/shell/extensions/switcher/matching "uint32 1"
    dconf write /org/gnome/shell/extensions/switcher/activate-by-key "uint32 2"

    dconf write /org/gnome/shell/extensions/paperwm/show-workspace-indicator false
    dconf write /org/gnome/shell/extensions/paperwm/show-window-position-bar false

    dconf write /org/gnome/shell/extensions/paperwm/cycle-width-steps "[0.3333, 0.5, 0.6667]"

    dconf write /org/gnome/shell/extensions/paperwm/selection-border-size 5
    dconf write /org/gnome/shell/extensions/paperwm/window-gap 12
    dconf write /org/gnome/shell/extensions/paperwm/horizontal-margin 12
    dconf write /org/gnome/shell/extensions/paperwm/vertical-margin 12
    dconf write /org/gnome/shell/extensions/paperwm/vertical-margin-bottom 12

    dconf write /org/gnome/desktop/screensaver/restart-enabled true
    dconf write /org/gnome/desktop/interface/font-antialiasing 'rgba'
    dconf write /org/gnome/mutter/center-new-windows true

    rewaita config
  }
}

def "main keybindings" [] {
  if not (has-cmd dconf) {
    error+ "dconf not found, skipping gnome keybindings"
    return
  }

  dconf write /org/gnome/shell/extensions/paperwm/keybindings/close-window "['<Super>BackSpace', '<Super>q']"

  dconf write /org/gnome/shell/extensions/paperwm/keybindings/switch-right "['<Super>Right']"
  dconf write /org/gnome/shell/extensions/paperwm/keybindings/switch-left "['<Super>Left']"
  dconf write /org/gnome/shell/extensions/paperwm/keybindings/switch-up "['<Super>Up']"
  dconf write /org/gnome/shell/extensions/paperwm/keybindings/switch-down "['<Super>Down']"

  dconf write /org/gnome/shell/extensions/paperwm/keybindings/move-up "['<Shift><Super>Up']"
  dconf write /org/gnome/shell/extensions/paperwm/keybindings/move-down "['<Shift><Super>Down']"
  dconf write /org/gnome/shell/extensions/paperwm/keybindings/move-left "['<Shift><Super>Left']"
  dconf write /org/gnome/shell/extensions/paperwm/keybindings/move-right "['<Shift><Super>Right']"

  dconf write /org/gnome/shell/extensions/paperwm/keybindings/switch-up-workspace "['<Super>Page_Up', '<Super><Control>Left']"
  dconf write /org/gnome/shell/extensions/paperwm/keybindings/switch-down-workspace "['<Super>Page_Down', '<Super><Control>Right']"
  dconf write /org/gnome/shell/extensions/paperwm/keybindings/move-up-workspace "['<Shift><Super>Page_Up', '<Super><Control><Shift>Left']"
  dconf write /org/gnome/shell/extensions/paperwm/keybindings/move-down-workspace "['<Shift><Super>Page_Down', '<Super><Control><Shift>Right']"

  dconf write /org/gnome/shell/extensions/paperwm/keybindings/new-window "['<Super>n']"

  dconf write /org/gnome/shell/extensions/paperwm/keybindings/move-monitor-above "@as []"
  dconf write /org/gnome/shell/extensions/paperwm/keybindings/move-monitor-below "@as []"
  dconf write /org/gnome/shell/extensions/paperwm/keybindings/move-monitor-left "@as []"
  dconf write /org/gnome/shell/extensions/paperwm/keybindings/move-monitor-right "@as []"
  dconf write /org/gnome/shell/extensions/paperwm/keybindings/move-space-monitor-above "@as []"
  dconf write /org/gnome/shell/extensions/paperwm/keybindings/move-space-monitor-below "@as []"
  dconf write /org/gnome/shell/extensions/paperwm/keybindings/move-space-monitor-left "@as []"
  dconf write /org/gnome/shell/extensions/paperwm/keybindings/move-space-monitor-right "@as []"
  dconf write /org/gnome/shell/extensions/paperwm/keybindings/open-window-position-down "@as []"
  dconf write /org/gnome/shell/extensions/paperwm/keybindings/open-window-position-left "@as []"
  dconf write /org/gnome/shell/extensions/paperwm/keybindings/swap-monitor-above "@as []"
  dconf write /org/gnome/shell/extensions/paperwm/keybindings/swap-monitor-below "@as []"
  dconf write /org/gnome/shell/extensions/paperwm/keybindings/swap-monitor-left "@as []"
  dconf write /org/gnome/shell/extensions/paperwm/keybindings/swap-monitor-right "@as []"
  dconf write /org/gnome/shell/extensions/paperwm/keybindings/switch-monitor-above "@as []"
  dconf write /org/gnome/shell/extensions/paperwm/keybindings/switch-monitor-below "@as []"
  dconf write /org/gnome/shell/extensions/paperwm/keybindings/switch-monitor-left "@as []"
  dconf write /org/gnome/shell/extensions/paperwm/keybindings/switch-monitor-right "@as []"
  dconf write /org/gnome/shell/extensions/paperwm/keybindings/switch-next "@as []"
  dconf write /org/gnome/shell/extensions/paperwm/keybindings/switch-previous "@as []"
  dconf write /org/gnome/desktop/wm/keybindings/show-desktop "@as []"

  dconf write /org/gnome/shell/extensions/dash-to-dock/hot-keys false
  dconf write /org/gnome/desktop/wm/preferences/num-workspaces 4
  dconf write /org/gnome/desktop/wm/keybindings/switch-to-workspace-1 "['<Super>1']"
  dconf write /org/gnome/desktop/wm/keybindings/switch-to-workspace-2 "['<Super>2']"
  dconf write /org/gnome/desktop/wm/keybindings/switch-to-workspace-3 "['<Super>3']"
  dconf write /org/gnome/desktop/wm/keybindings/switch-to-workspace-4 "['<Super>4']"
  dconf write /org/gnome/desktop/wm/preferences/workspace-names "['1', '2', '3', '4']"

  gnome-shortcut.nu create "Terminal" -c "ptyxis -s" -s "<Super>Return"
}

def "main jetbrains mono" [] {
  if (is-nixos) {
    warn+ "jetbrains mono install: nixos not supported"
    return
  }

  jetbrains-mono-install
}

def "main jetbrains mono fix" [] {
  grep -rlF 'Cascadia Mono NF' .
  | lines
  | each {|f| sed -i 's/Cascadia Mono NF/JetBrainsMono Nerd Font/g' $f }
}

def "font exists" [font_name: string] {
  (fc-list : family
  | lines
  | each {|line| $line | split row "," }
  | flatten
  | each {|name| $name | str trim }
  | any {|name| $name == $font_name })
}

def is-flatpak [name: string] {
  (flatpak list --columns=application | str contains $name)
}

def "main ptyxis" [] {
  if not (has-cmd gsettings) {
    error+ "gsettings not found, skipping Ptyxis configuration"
    return
  }
  if not (has-cmd dconf) {
    error+ "dconf not found, skipping Ptyxis configuration"
    return
  }
  if not (has-cmd ptyxis) and not (is-flatpak "org.gnome.Ptyxis") {
    if not (is-fedora-atomic) {
      log+ "ptyxis not found, Installing..."
      si ["ptyxis"]
    }
  }

  log+ "Configuring Ptyxis"

  gsettings set org.gnome.Ptyxis use-system-font false
  gsettings set org.gnome.Ptyxis interface-style 'system'

  if (font exists 'JetBrainsMono Nerd Font') {
    gsettings set org.gnome.Ptyxis font-name 'JetBrainsMono Nerd Font 11'
  } else if (font exists 'Cascadia Mono NF') {
    gsettings set org.gnome.Ptyxis font-name 'Cascadia Mono NF 11'
  }

  let profid = (
    gsettings get org.gnome.Ptyxis default-profile-uuid
    | str trim --char "'"
  )
  if ($profid == "") {
    error+ "No default profile. Open ptyxis and run 'gnome.nu ptyxis'."
    return
  }

  let profile = $"org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/($profid)/"
  gsettings set $profile opacity 0.85
  gsettings set $profile palette "Catppuccin Mocha"
}

def "main gdm" [] {
  if not (is-arch) and not (is-fedora) and not (is-resolute) and not (is-tw) {
    error+ "Currently only archlinux, fedora, tumbleweed and ubuntu 26.04 supported"
    return
  }

  mut pkgs = [
    "gnome-control-center"
    "gnome-disk-utility"
    "gnome-power-manager"
    "gnome-system-monitor"
    "imv"
    "mpv"
    "nautilus"
    "papers"
    "udiskie"
    "udisks2"
  ]

  if (is-arch) {
    $pkgs = $pkgs ++ [
      "archlinux-wallpaper"
      "extension-manager"
      "gdm"
      "gvfs-nfs"
      "gvfs-smb"
      "python-pipx"
    ]
  } else if (is-tw) {
    $pkgs = $pkgs ++ [
      "extension-manager"
      "flatpak-xdg-utils"
      "gdm"
      "gvfs-backend-samba"
      "python3-pipx"
      "xdg-utils"
      wallpaper-branding-openSUSE
    ]
  } else if (is-fedora) {
    $pkgs = $pkgs ++ [
      "gdm"
      "gnome-extensions-app"
      "google-noto-color-emoji-fonts"
      "gvfs-nfs"
      "gvfs-smb"
      "pipx"
      "xdg-utils"
    ]
  } else if (is-resolute) {
    $pkgs = $pkgs ++ [
      "gdm3"
      "gnome-shell-extension-manager"
      "gvfs"
      "gvfs-backends"
      "pipx"
      "xdg-utils"
    ]
  }

  log+ "Installing gdm packages..."
  si $pkgs
}

def "main help" [] {
  print $"Usage: gnome.nu <command>

  Available commands:
  extensions      Install GNOME extensions\(paperwm etc\)
  settings        Configure GNOME settings
  keybindings     Configure GNOME keybindings
  flatpaks        Manage GNOME flatpaks
  ptyxis          Configure Ptyxis terminal
  gdm             Minimal Gnome system with gdm display manager
  rewaita config  Rewaita defaults for gnome config
  jetbrains mono  Install JetBrains Mono Nerd Font
  vicinae         Install and setup vicinae for gnome
  help            Show this help message

  "
}

def "main" [] {
  if not (has-cmd pipx) {
    error+ "pipx not installed. Quitting"
    return
  }

  bootstrap
  main extensions
  main settings
  main keybindings
  main jetbrains mono
  main flatpaks
  main ptyxis
}
