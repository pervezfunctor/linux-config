#!/usr/bin/env bash
#
# setup.sh — Idempotent dev environment bootstrap
#
# Detects Ubuntu/Debian or Fedora then installs and configures:
#   system packages, fish, starship, uv, C++ tools, Homebrew,
#   modern CLI tools, Zed, Alacritty, JetBrains Mono Nerd Font,
#   and dotfiles (fish, alacritty, zed, tmux) + Neovim (AstroNvim).
#
# Usage:
#   ./setup.sh
#
# Requirements:
#   - ~/.linux-config already cloned (or symlinked) at script location
#   - sudo access
#

set -euo pipefail

# ---------------------------------------------------------------------------
# Colors (no-op when not a TTY)
# ---------------------------------------------------------------------------
setup_colors() {
  if [[ -t 1 ]]; then
    BOLD='\033[1m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    RED='\033[0;31m'
    NC='\033[0m'
  else
    BOLD=''
    GREEN=''
    YELLOW=''
    RED=''
    NC=''
  fi
}

info() { printf "${BOLD}${GREEN}[INFO]${NC}  %s\n" "$*"; }
warn() { printf "${BOLD}${YELLOW}[WARN]${NC}  %s\n" "$*"; }
error() { printf "${BOLD}${RED}[ERROR]${NC} %s\n" "$*" >&2; }

# ---------------------------------------------------------------------------
# OS detection — sets global OS to "ubuntu" or "fedora"
# ---------------------------------------------------------------------------
detect_os() {
  if command -v apt &>/dev/null; then
    OS="ubuntu"
  elif command -v dnf &>/dev/null; then
    OS="fedora"
  else
    error "Unsupported OS — only Debian/Ubuntu and Fedora are supported."
    exit 1
  fi
  info "Detected OS: ${OS}"
}

# ---------------------------------------------------------------------------
# Ensure we have sudo upfront
# ---------------------------------------------------------------------------
ensure_sudo() {
  if [[ $EUID -ne 0 ]]; then
    info "Elevating privileges…"
    sudo -v || {
      error "sudo required"
      exit 1
    }
  fi
}

# ===========================================================================
# Installation steps (all idempotent)
# ===========================================================================

# -- 1. System update -------------------------------------------------------
update_system() {
  info "Updating system packages…"
  case "${OS}" in
  ubuntu) sudo apt update && sudo apt upgrade -y ;;
  fedora) sudo dnf update -y ;;
  esac
}

# -- 2. Essential packages --------------------------------------------------
install_essentials() {
  info "Installing essential packages…"
  case "${OS}" in
  ubuntu)
    sudo apt install -y curl git-core wget trash-cli build-essential tar unzip zip
    ;;
  fedora)
    sudo dnf install -y curl git-core wget trash-cli gcc make tar unzip zip
    ;;
  esac
}

# -- 3. Fish shell ----------------------------------------------------------
install_fish() {
  if command -v fish &>/dev/null; then
    info "fish already installed, skipping."
    return 0
  fi
  info "Installing fish shell…"
  case "${OS}" in
  ubuntu) sudo apt install -y fish ;;
  fedora) sudo dnf install -y fish ;;
  esac
}

set_fish_default() {
  local fish_path
  fish_path="$(command -v fish)"
  local current_shell
  current_shell="$(grep "^${USER}:" /etc/passwd 2>/dev/null | cut -d: -f7 || true)"
  if [[ "${current_shell}" == "${fish_path}" ]]; then
    info "fish is already the default shell."
    return 0
  fi
  info "Setting fish as the default shell…"
  sudo chsh -s "${fish_path}" "${USER}"
  warn "Log out and back in (or reboot) for the change to take effect."
}

# -- 4. Starship prompt -----------------------------------------------------
install_starship() {
  if command -v starship &>/dev/null; then
    info "starship already installed, skipping."
    return 0
  fi
  info "Installing starship prompt…"
  case "${OS}" in
  ubuntu) sudo apt install -y starship ;;
  fedora) curl -sS https://starship.rs/install.sh | sh ;;
  esac
}

# -- 5. uv (Python) ---------------------------------------------------------
install_uv() {
  if command -v uv &>/dev/null; then
    info "uv already installed, skipping."
    return 0
  fi
  info "Installing uv (Python package manager)…"
  curl -LsSf https://astral.sh/uv/install.sh | sh
}

# -- 6. C++ tools -----------------------------------------------------------
install_cpp_tools() {
  info "Installing C/C++ development tools…"
  case "${OS}" in
  ubuntu)
    sudo apt install -y clang cmake entr gcc make pkg-config clang-tools
    ;;
  fedora)
    sudo dnf install -y clang cmake entr gcc make pkg-config clang-tools-extra
    ;;
  esac
}

# -- 7. Homebrew ------------------------------------------------------------
install_homebrew() {
  if command -v brew &>/dev/null; then
    info "Homebrew already installed, skipping."
    return 0
  fi
  info "Installing Homebrew…"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
}

# -- 8. Modern CLI tools via brew -------------------------------------------
install_brew_tools() {
  info "Installing modern CLI tools via Homebrew…"
  local tools
  tools="trash-cli fzf eza zoxide bat gh ripgrep tealdeer direnv fd jq bottom htop"
  local tool
  for tool in ${tools}; do
    if command -v "${tool}" &>/dev/null; then
      info "${tool} already installed, skipping."
    else
      brew install "${tool}"
    fi
  done
}

# -- 9. Zed editor ----------------------------------------------------------
install_zed() {
  if command -v zed &>/dev/null || command -v zed-editor &>/dev/null; then
    info "Zed editor already installed, skipping."
    return 0
  fi
  info "Installing Zed editor…"
  curl -f https://zed.dev/install.sh | sh
}

# -- 10. JetBrains Mono Nerd Font -------------------------------------------
install_font() {
  if brew list --cask font-jetbrains-mono-nerd-font &>/dev/null; then
    info "JetBrains Mono Nerd Font already installed, skipping."
    return 0
  fi
  info "Installing JetBrains Mono Nerd Font…"
  brew install --cask font-jetbrains-mono-nerd-font
}

# -- 11. Alacritty terminal -------------------------------------------------
install_alacritty() {
  if command -v alacritty &>/dev/null; then
    info "Alacritty already installed, skipping."
    return 0
  fi
  info "Installing Alacritty terminal…"
  case "${OS}" in
  ubuntu) sudo apt install -y alacritty ;;
  fedora) sudo dnf install -y alacritty ;;
  esac
}

# -- 12. Dotfiles (must happen AFTER brew so fish_add_path works) -----------
setup_dotfiles() {
  local repo_dir
  repo_dir="${HOME}/.linux-config"
  if [[ ! -d "${repo_dir}" ]]; then
    error "Repository not found at ${repo_dir}. Clone it first:"
    error "  git clone https://github.com/pervezfunctor/linux-config.git ~/.linux-config"
    exit 1
  fi

  info "Setting up fish configuration…"
  mkdir -p "${HOME}/.config/fish"
  cp "${repo_dir}/fish/dot-config/fish/config.fish" "${HOME}/.config/fish/config.fish"

  info "Setting up Alacritty configuration…"
  mkdir -p "${HOME}/.config/alacritty"
  cp "${repo_dir}/alacritty/dot-config/alacritty/alacritty.toml" "${HOME}/.config/alacritty/alacritty.toml"

  info "Setting up Zed editor configuration…"
  mkdir -p "${HOME}/.config/zed"
  cp "${repo_dir}/zed/dot-config/zed/settings.json" "${HOME}/.config/zed/settings.json"

  info "Setting up tmux configuration…"
  mkdir -p "${HOME}/.config/tmux"
  cp "${repo_dir}/tmux/dot-config/tmux/tmux.conf" "${HOME}/.config/tmux/tmux.conf"
}

# -- 13. Neovim + AstroNvim -------------------------------------------------
install_neovim() {
  if command -v nvim &>/dev/null; then
    info "Neovim already installed, skipping."
    return 0
  fi
  info "Installing Neovim…"
  brew install neovim
}

setup_neovim() {
  local repo_dir nvim_dir
  repo_dir="${HOME}/.linux-config"
  nvim_dir="${HOME}/.config/nvim"

  if [[ -f "${nvim_dir}/lua/community.lua" ]]; then
    info "AstroNvim configuration already exists, skipping."
    return 0
  fi

  info "Setting up AstroNvim…"
  mkdir -p "${nvim_dir}"
  rm -rf "${nvim_dir}"
  mkdir -p "${nvim_dir}"
  git clone --depth 1 https://github.com/AstroNvim/template "${nvim_dir}"
  rm -rf "${nvim_dir}/.git"
  cp "${repo_dir}/nvim/dot-config/nvim/lua/community.lua" "${nvim_dir}/lua/community.lua"
  cp -r "${repo_dir}/nvim/dot-config/nvim/lua/plugins/" "${nvim_dir}/lua/plugins/"
}

# ===========================================================================
# Main
# ===========================================================================
main() {
  export PATH="/home/linuxbrew/.linuxbrew/bin:${PATH}"

  setup_colors
  detect_os

  info "Starting idempotent dev-environment setup (alacritty + zed)…"
  echo ""

  ensure_sudo
  update_system
  install_essentials
  install_fish
  set_fish_default
  install_starship
  install_uv
  install_cpp_tools
  install_homebrew
  install_brew_tools
  install_zed
  install_font
  install_alacritty
  setup_dotfiles
  install_neovim
  setup_neovim

  echo ""
  info "All done! Restart your terminal to enjoy your new environment."
}

main "$@"
