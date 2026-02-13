#!/bin/bash

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
echo "REPO_ROOT is set to: $REPO_ROOT"

GO_VERSION_DEFAULT="1.22.2"

install_macos() {
  echo "Detected MacOS"

  if ! command -v brew &>/dev/null; then
    echo "Homebrew not found. Installing..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  # Note: some of these are formula taps; brew install handles them.
  brew_packages=("starship" "neovim" "tmux" "joshmedeski/sesh/sesh" "zoxide" "fzf")
  for pkg in "${brew_packages[@]}"; do
    echo "Ensuring $pkg is installed..."
    brew list "$pkg" &>/dev/null || brew install "$pkg"
  done
}

install_linux_packages() {
  # Install base deps using the first available package manager.
  if command -v apt-get &>/dev/null; then
    sudo apt-get update
    sudo apt-get install -y curl git zsh npm unzip tmux ca-certificates
    return
  fi

  if command -v dnf &>/dev/null; then
    sudo dnf install -y curl git zsh npm unzip tmux ca-certificates
    return
  fi

  if command -v pacman &>/dev/null; then
    sudo pacman -S --noconfirm curl git zsh npm unzip tmux ca-certificates
    return
  fi

  if command -v zypper &>/dev/null; then
    sudo zypper install -y curl git zsh npm unzip tmux ca-certificates
    return
  fi

  echo "No supported package manager found (apt-get/dnf/pacman/zypper)." >&2
  exit 1
}

install_go_linux() {
  if command -v go &>/dev/null; then
    echo "go already installed. Skipping..."
    return
  fi

  local go_version="${GO_VERSION:-$GO_VERSION_DEFAULT}"
  local arch
  arch="$(uname -m)"

  local go_arch
  case "$arch" in
    x86_64|amd64) go_arch="amd64" ;;
    aarch64|arm64) go_arch="arm64" ;;
    armv7l) go_arch="armv6l" ;; # best-effort; adjust if you actually need armv7
    *)
      echo "Unsupported architecture for Go install: $arch" >&2
      exit 1
      ;;
  esac

  echo "Installing go ${go_version} for linux-${go_arch}..."
  local tgz="go${go_version}.linux-${go_arch}.tar.gz"

  curl -fsSLO "https://go.dev/dl/${tgz}"
  sudo rm -rf /usr/local/go
  sudo tar -C /usr/local -xzf "${tgz}"
  rm -f "${tgz}"

  echo "go installed. (Ensure /usr/local/go/bin is on PATH; your dotfiles .zshrc already sets it.)"
}

install_neovim_linux() {
  if command -v nvim &>/dev/null; then
    echo "nvim already installed. Skipping..."
    return
  fi

  local arch
  arch="$(uname -m)"

  # Prefer distro packages when available (especially on Raspberry Pi / arm64)
  if command -v apt-get &>/dev/null; then
    echo "Installing Neovim via apt-get..."
    sudo apt-get install -y neovim || true
  fi

  if command -v nvim &>/dev/null; then
    return
  fi

  echo "Neovim not available via package manager (or install failed). Installing from upstream release..."

  if [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then
    local tarball="nvim-linux-arm64.tar.gz"
    curl -fsSLO "https://github.com/neovim/neovim/releases/latest/download/${tarball}"
    sudo rm -rf /opt/nvim
    sudo mkdir -p /opt/nvim
    sudo tar -C /opt/nvim --strip-components=1 -xzf "${tarball}"
    rm -f "${tarball}"
    sudo ln -sfn /opt/nvim/bin/nvim /usr/local/bin/nvim
  else
    # x86_64 fallback: AppImage
    curl -fsSLO https://github.com/neovim/neovim/releases/latest/download/nvim.appimage
    chmod u+x nvim.appimage
    sudo mv nvim.appimage /usr/local/bin/nvim
  fi
}

install_linux() {
  echo "Detected Linux"

  install_linux_packages
  install_go_linux
  install_neovim_linux

  # Install sesh
  if ! command -v sesh &>/dev/null; then
    echo "Installing sesh..."
    # default target: ~/go/bin (ensure it exists; your dotfiles .zshrc sets PATH)
    mkdir -p "$HOME/go/bin"
    /usr/local/go/bin/go install github.com/joshmedeski/sesh@latest || go install github.com/joshmedeski/sesh@latest
  fi

  # Install zoxide
  if ! command -v zoxide &>/dev/null; then
    echo "Installing zoxide..."
    curl -fsSL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
  fi

  # Install fzf
  if ! command -v fzf &>/dev/null; then
    echo "Installing fzf..."
    if [ ! -d "$HOME/.fzf" ]; then
      git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
    fi
    # Non-interactive install: enable completion + keybindings, don't try to edit rc files
    "$HOME/.fzf/install" --key-bindings --completion --no-update-rc --no-bash --no-fish || true
  fi
}

install_oh_my_zsh() {
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "Installing oh-my-zsh..."
    # Note: oh-my-zsh installer can try to switch shells; keep it as-is for now.
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  else
    echo "oh-my-zsh already installed. Skipping..."
  fi

  # Ensure commonly used plugins exist (your .zshrc enables them)
  local zsh_custom
  zsh_custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  mkdir -p "$zsh_custom/plugins"

  if [ ! -d "$zsh_custom/plugins/zsh-autosuggestions" ]; then
    echo "Installing zsh-autosuggestions..."
    git clone https://github.com/zsh-users/zsh-autosuggestions "$zsh_custom/plugins/zsh-autosuggestions"
  fi

  if [ ! -d "$zsh_custom/plugins/zsh-syntax-highlighting" ]; then
    echo "Installing zsh-syntax-highlighting..."
    git clone https://github.com/zsh-users/zsh-syntax-highlighting "$zsh_custom/plugins/zsh-syntax-highlighting"
  fi
}

install_starship() {
  if ! command -v starship &>/dev/null; then
    echo "Installing starship..."
    mkdir -p "$HOME/.local/bin"
    curl -fsSL https://starship.rs/install.sh | sh -s -- -y -b "$HOME/.local/bin"
    echo "starship installed. (Ensure ~/.local/bin is on PATH; your dotfiles .zshrc already sets it.)"
  else
    echo "starship already installed. Skipping..."
  fi
}

install_tmux_plugins() {
  if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
    echo "Installing tmux plugin manager (tpm)..."
    mkdir -p "$HOME/.tmux/plugins"
    git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
  else
    echo "tmux plugins already installed. Skipping..."
  fi
}

OS="$(uname)"
case "$OS" in
  Darwin)
    install_macos
    install_oh_my_zsh
    install_starship
    install_tmux_plugins
    ;;
  Linux)
    install_linux
    install_oh_my_zsh
    install_starship
    install_tmux_plugins
    ;;
  *)
    echo "Unsupported OS: $OS" >&2
    exit 1
    ;;
esac

# Keep these idempotent even if already called above
install_oh_my_zsh
install_starship

echo "Dependencies installed!"
echo "Creating symlinks..."

create_symlink() {
  local target="$1"
  local link_name="$2"

  mkdir -p "$(dirname "$link_name")"

  if [ -e "$link_name" ] || [ -L "$link_name" ]; then
    local timestamp
    timestamp=$(date +"%Y%m%d")
    local backup_name="${link_name}.backup.${timestamp}"
    echo "$link_name exists, backing up to $backup_name"
    mv "$link_name" "$backup_name"
  fi

  ln -sfn "$target" "$link_name"
  echo "Created symlink for $target at $link_name"
}

create_symlink "$REPO_ROOT/.zshrc" "$HOME/.zshrc"
create_symlink "$REPO_ROOT/nvim" "$HOME/.config/nvim"
create_symlink "$REPO_ROOT/starship.toml" "$HOME/.config/starship.toml"
create_symlink "$REPO_ROOT/wezterm" "$HOME/.config/wezterm"
rm -f "$REPO_ROOT/wezterm/wezterm"

# Copy to clipboard functionality on Windows WSL2
create_symlink "$REPO_ROOT/xsel" "$HOME/bin/xsel"

rm -f "$HOME/.config/nvim/nvim"
create_symlink "$REPO_ROOT/.tmux.conf" "$HOME/.tmux.conf"
create_symlink "$REPO_ROOT/tmux-sesh-selector.sh" "$HOME/tmux-sesh-selector.sh"

echo "Done!"
echo "Please restart your shell to apply changes"
