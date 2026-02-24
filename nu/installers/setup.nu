#! /usr/bin/env nu

export-env {
  $env.DOT_DIR = $"($env.HOME)/linux-config"
}

def "main setup-shell" [] {
  nu $"($env.DOT_DIR)/bin/setup-shell.nu"
}

def "main setup-desktop" [] {
  nu $"($env.DOT_DIR)/bin/setup-desktop.nu"
}

def main [] {
  main setup-shell
  main setup-desktop
}
