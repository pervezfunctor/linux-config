#! /usr/bin/env nu

export-env {
  $env.DOT_DIR = $"($env.HOME)/.local/share/linux-config"
}

def "main setup-shell" [] {
  nu $"($env.DOT_DIR)/nu/installers/setup-shell.nu"
}

def "main setup-desktop" [] {
  nu $"($env.DOT_DIR)/nu/installers/setup-desktop.nu"
}

def main [] {
  bootstrap
  main setup-shell
  main setup-desktop
}
