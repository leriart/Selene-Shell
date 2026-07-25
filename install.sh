#!/usr/bin/env bash
# Selene installer.
#
# Mirrors the Ambxst installer philosophy:
#   - one curl|sh invocation,
#   - clones to ~/.local/src/selene-shell and builds there,
#   - only touches PATH files inside the user's home (no sudo),
#   - never edits an existing config without a marker the user can remove.
#
# Layout produced:
#   ~/.local/src/selene-shell/      repo source
#   ~/.local/share/selene/          generated data (hyprland config, state)
#   ~/.local/bin/selene             symlink to <src>/cli.sh

set -euo pipefail

SELENE_REPO="${SELENE_REPO:-https://github.com/leriart/selene-shell.git}"
SELENE_BRANCH="${SELENE_BRANCH:-main}"
SELENE_SRC="${SELENE_SRC:-$HOME/.local/src/selene-shell}"
SELENE_HOME="${SELENE_HOME:-$HOME/.local/share/selene}"
SELENE_BIN_DIR="${SELENE_BIN_DIR:-$HOME/.local/bin}"

c_blue='\033[1;34m'; c_green='\033[1;32m'; c_yellow='\033[1;33m'; c_red='\033[1;31m'; c_reset='\033[0m'

log()   { printf "${c_blue}[selene]${c_reset} %s\n" "$*"; }
ok()    { printf "${c_green}[ selene ok  ]${c_reset} %s\n" "$*"; }
warn()  { printf "${c_yellow}[ selene warn ]${c_reset} %s\n" "$*" >&2; }
die()   { printf "${c_red}[ selene fail ]${c_reset} %s\n" "$*" >&2; exit 1; }

require() {
  for tool in "$@"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      die "missing required tool: $tool"
    fi
  done
}

detect_distro() {
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    case "${ID:-unknown}" in
      arch|archcraft|endeavouros|garuda|manjaro) echo arch ;;
      fedora|nobara)                             echo fedora ;;
      nixos)                                     echo nixos ;;
      ubuntu|pop|debian|mint)                    echo debian ;;
      *) echo "unknown:${ID:-?}" ;;
    esac
  else
    echo "unknown:none"
  fi
}

install_deps() {
  local distro="$1"
  case "$distro" in
    arch)
      log "Detected Arch-based system. Installing build dependencies via pacman..."
      sudo pacman -S --needed --noconfirm \
        qt6-base qt6-declarative qt6-quickcontrols2 \
        cmake ninja gcc \
        rust cargo \
        git base-devel
      ;;
    fedora)
      log "Detected Fedora. Installing build dependencies via dnf..."
      sudo dnf install -y \
        qt6-qtbase-devel qt6-qtdeclarative-devel qt6-qtquickcontrols2-devel \
        cmake ninja-build gcc gcc-c++ \
        rust cargo \
        git
      ;;
    nixos)
      log "Detected NixOS. Use the Selene flake for a fully reproducible build:"
      log "  nix run github:${SELENE_REPO%.git}/${SELENE_BRANCH}"
      return 1
      ;;
    debian)
      log "Detected Debian/Ubuntu. Installing build dependencies via apt..."
      sudo apt update
      sudo apt install -y \
        qt6-base-dev qt6-declarative-dev qt6-quickcontrols2-dev \
        cmake ninja-build build-essential \
        rustc cargo \
        git
      ;;
    *)
      warn "Unknown distro. Skipping automatic dependency install."
      warn "Selene needs Qt 6 (qt6-base, qt6-declarative, qt6-quickcontrols2),"
      warn "CMake >= 3.24, Ninja, a C++17 compiler, and the Rust toolchain."
      ;;
  esac
}

clone_or_update() {
  if [[ -d "$SELENE_SRC/.git" ]]; then
    log "Selene source already present at $SELENE_SRC. Updating..."
    git -C "$SELENE_SRC" fetch --quiet
    git -C "$SELENE_SRC" checkout --quiet "$SELENE_BRANCH"
    git -C "$SELENE_SRC" pull --ff-only --quiet
  else
    log "Cloning selene-shell ($SELENE_BRANCH) into $SELENE_SRC..."
    mkdir -p "$(dirname "$SELENE_SRC")"
    git clone --branch "$SELENE_BRANCH" --depth 1 "$SELENE_REPO" "$SELENE_SRC"
  fi
}

build_selene() {
  log "Generating Cargo dependency lockfile..."
  ( cd "$SELENE_SRC" && cargo generate-lockfile --manifest-path rust/Cargo.toml )
  log "Configuring CMake build (Release)..."
  ( cd "$SELENE_SRC" && cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release )
  log "Building selene-shell (this may take a while on first build)..."
  ( cd "$SELENE_SRC" && cmake --build build )
  ok "Build complete -> $SELENE_SRC/build/selene-shell"
}

install_cli() {
  mkdir -p "$SELENE_BIN_DIR"
  local target="$SELENE_BIN_DIR/selene"
  if [[ -e "$target" && ! -L "$target" ]]; then
    warn "$target exists and is not a symlink. Leaving it untouched."
    warn "Run: ln -sf $SELENE_SRC/cli.sh $target"
    return 0
  fi
  ln -sfn "$SELENE_SRC/cli.sh" "$target"
  ok "Installed CLI -> $target"
  if [[ ":$PATH:" != *":$SELENE_BIN_DIR:"* ]]; then
    warn "$SELENE_BIN_DIR is not in PATH for this shell."
    warn "Add it:  export PATH=\"$SELENE_BIN_DIR:\$PATH\""
  fi
}

stage_share() {
  mkdir -p "$SELENE_HOME"
  ok "Data directory ready -> $SELENE_HOME"
}

prompt_hyprland() {
  if ! command -v hyprctl >/dev/null 2>&1; then
    log "hyprctl not detected. Skipping compositor integration."
    return 0
  fi
  local reply
  read -r -p "Install the Hyprland source line now? [y/N] " reply
  if [[ "$reply" =~ ^[Yy]$ ]]; then
    "$SELENE_BIN_DIR/selene" install hyprland || warn "Hyprland integration returned non-zero. Run 'selene install hyprland' later."
  fi
}

main() {
  log "Selene installer (branch: $SELENE_BRANCH)"
  require git
  require bash

  local distro
  distro="$(detect_distro)"
  log "Distro: $distro"

  if [[ "$distro" != nixos ]]; then
    install_deps "$distro" || warn "Dependency install skipped or partial. Continuing anyway."
  fi

  clone_or_update
  stage_share
  build_selene
  install_cli

  ok "Selene installed."
  echo
  echo "  Run the shell      :  selene"
  echo "  Integrate Hyprland :  selene install hyprland"
  echo "  Update later       :  selene update"
  echo
  prompt_hyprland
}

main "$@"
