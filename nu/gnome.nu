#!/usr/bin/env nu

use std/log
use ./lib.nu *

def "main extensions" [] {
  if not (has-cmd gext) {
    if not (has-cmd pipx) {
      log error "pipx not found, skipping gnome extensions"
      return
    }
    pipx install gnome-extensions-cli --system-site-packages
  }

  if not (has-cmd gext) {
    log error "gext not found, skipping gnome extensions"
    return
  }

  let extensions = [
    "paperwm@paperwm.github.com"
    "switcher@landau.fi"
    "windowsNavigator@gnome-shell-extensions.gcampax.github.com"
    "blur-my-shell@aunetx"
    user-theme@gnome-shell-extensions.gcampax.github.com
  ]

  for ext in $extensions {
    do -i { gext install $ext }
    do -i { gext enable $ext }
  }
}

def "main flatpaks" [] {
  if not (has-cmd flatpak) {
    log error "flatpak not found, skipping gnome flatpaks"
    return
  }

  ui.nu flathub

  let flatpaks = [
    "com.mattjakeman.ExtensionManager"
    "org.gtk.Gtk3theme.adw-gtk3"
    "org.gtk.Gtk3theme.adw-gtk3-dark"
    "io.github.swordpuffin.rewaita"
  ]
  for pkg in $flatpaks {
    do -i { flatpak --user install -y flathub $pkg }
  }

  do -i {
    flatpak --user override --filesystem=xdg-config/gtk-3.0:rw
    flatpak --user override --filesystem=xdg-config/gtk-4.0:rw
  }
}

def "main settings" [] {
  if not (has-cmd gsettings) {
    log error "gsettings not found, skipping gnome settings"
    return
  }

  gsettings set org.gnome.desktop.input-sources xkb-options "['caps:ctrl_modifier']"
  gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
  gsettings set org.gnome.desktop.interface accent-color 'green'
  gsettings set org.gnome.desktop.interface gtk-key-theme "Emacs"
  gsettings set org.gnome.desktop.wm.preferences resize-with-right-button true

  gsettings set org.gnome.mutter dynamic-workspaces false
  gsettings set org.gnome.desktop.wm.preferences num-workspaces 4

  if not (has-cmd dconf) {
    log error "dconf not found, skipping gnome settings"
    return
  }

  do -i {
    dconf write /org/gnome/shell/extensions/blur-my-shell/panel/blur "false"
    dconf write /org/gnome/shell/extensions/blur-my-shell/applications/whitelist "['org.gnome.Ptyxis', 'dev.zed.Zed']"

    dconf write /org/gnome/shell/extensions/switcher/max-width-percentage "uint32 25"
    dconf write /org/gnome/shell/extensions/switcher/font-size "uint32 16"
    dconf write /org/gnome/shell/extensions/switcher/icon-size "uint32 16"

    dconf write /org/gnome/shell/extensions/paperwm/show-workspace-indicator false
    dconf write /org/gnome/shell/extensions/paperwm/show-window-position-bar false

    dconf write /org/gnome/shell/extensions/paperwm/cycle-width-steps "[0.3333, 0.5, 0.6667]"

    dconf write /org/gnome/shell/extensions/paperwm/selection-border-size 5
    dconf write /org/gnome/shell/extensions/paperwm/window-gap 12
    dconf write /org/gnome/shell/extensions/paperwm/horizontal-margin 12
    dconf write /org/gnome/shell/extensions/paperwm/vertical-margin 12
    dconf write /org/gnome/shell/extensions/paperwm/vertical-margin-bottom 12
  }
}

def "main keybindings" [] {
  if not (has-cmd dconf) {
    log error "dconf not found, skipping gnome keybindings"
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

  # dconf write /org/gnome/shell/extensions/search-light/secondary-shortcut-search "['<Super>d']"
  # dconf write /org/gnome/shell/extensions/search-light/primary-shortcut-search "['<Super>Space']"
}

def "main jetbrains mono" [] {
    if (fc-list | lines | where $it =~ "(?i)jetbrains.*nerd" | is-not-empty) {
      log+ "JetBrains Mono Nerd Font already installed"
      return
    }
    log+ "Installing JetBrains Mono Nerd Font"
    mkdir ~/.local/share/fonts
    rm -rf /tmp/jetbrains-mono.zip /tmp/jetbrains-mono
    wget -nv https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/JetBrainsMono.zip -O /tmp/jetbrains-mono.zip
    unzip -qq -d /tmp/jetbrains-mono -o /tmp/jetbrains-mono.zip
    glob "/tmp/jetbrains-mono/*.ttf" | each { |f| cp $f ~/.local/share/fonts/ }
    rm -rf /tmp/jetbrains-mono.zip /tmp/jetbrains-mono
    log+ "JetBrains Mono Nerd Font installation done!"
}

def "main jetbrains mono fix" [] {
  grep -rlF 'Cascadia Mono NF' .
  | lines
  | each {|f| sed -i 's/Cascadia Mono NF/JetBrainsMono Nerd Font/g' $f }
}

def "main help" [] {
  print $"Usage: gnome.nu <command>
  Available commands:
  extensions     Install GNOME extensions\(paperwm etc\)
  packages       Install GNOME packages
  settings       Configure GNOME settings
  keybindings    Configure GNOME keybindings
  flatpaks       Manage GNOME flatpaks
  ptyxis         Configure Ptyxis terminal
  jetbrains mono Install JetBrains Mono Nerd Font
  help           Show this help message
  "
}

def is-flatpak [name: string] {
  (flatpak list --columns=application | str contains $name)
}

def "font exists" [font_name: string] {
  (fc-list : family
  | lines
  | each {|line| $line | split row "," }
  | flatten
  | each {|name| $name | str trim }
  | any {|name| $name == $font_name })
}

def "main ptyxis" [] {
  if not (has-cmd gsettings) {
    log error "gsettings not found, skipping Ptyxis configuration"
    return
  }
  if not (has-cmd dconf) {
    log error "dconf not found, skipping Ptyxis configuration"
    return
  }
  if not (has-cmd ptyxis) and not (is-flatpak "org.gnome.Ptyxis") {
    log info "ptyxis not found, Installing..."
    if (is-atomic) {
      fpi "org.gnome.Ptyxis"
    } else {
      si ["ptyxis"]
    }
  }

  log info "Configuring Ptyxis"

  gsettings set org.gnome.Ptyxis use-system-font false
  gsettings set org.gnome.Ptyxis interface-style 'system'

  if (font exists 'Cascadia Mono NF') {
    gsettings set org.gnome.Ptyxis font-name 'Cascadia Mono NF 11'
  } else if (font exists '') {
    gsettings set org.gnome.Ptyxis font-name ''
  }

  let profid = (
    gsettings get org.gnome.Ptyxis default-profile-uuid
    | str trim --char "'"
  )

  let profile = $"org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/($profid)/"
  gsettings set $profile opacity 0.85
  gsettings set $profile palette "Everforest"

  if (is-atomic) {
    gsettings set $profile custom-command '/usr/bin/fish'
  }

  # is flatpak
  # let profid = (
  #   flatpak run --command=gsettings app.devsuite.Ptyxis \
  #     get org.gnome.Ptyxis default-profile-uuid
  #   | str trim --char "'"
  # )

  # flatpak run --command=gsettings app.devsuite.Ptyxis \
  #   set $"org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/($profid)/" \
  #   opacity 0.85

  # flatpak run --command=gsettings app.devsuite.Ptyxis \
  #   set $"org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/($profid)/" \
  #   palette "Everforest"
}

def "main packages" [] {
  if (is-atomic) {
    log info "Skipping package installation on atomic"
    return
  }

  log info "Installing packages..."
  do -i {
    si ["gnome-tweaks"]
  }
}

def "main" [] {
  fonts
  main packages
  main extensions
  main settings
  main keybindings
  main flatpaks
  main ptyxis
}
