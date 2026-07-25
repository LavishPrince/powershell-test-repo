#!/bin/bash

set -euo pipefail

source "$HOME/.bashrc"

# ──────────────────────────────────────────────────
# Update package lists
# ──────────────────────────────────────────────────
sudo apt update

# ──────────────────────────────────────────────────
# Apt prerequisites (graphical packages removed:
#   feh, i3, polybar, picom, rofi)
# ──────────────────────────────────────────────────
apt_packages=(
    "ansible"
    "build-essential"
    "curl"
    "file"
    "git"
    "ruby"
    "ruby-dev"
    "nodejs"
    "npm"
    "apt-transport-https"
    "ca-certificates"
    "gnupg"
    "lsb-release"
)

for package in "${apt_packages[@]}"; do
    sudo apt install -y "$package"
done

echo "✅ Prerequisites installed successfully!"

# ──────────────────────────────────────────────────
# Node.js via n
# ──────────────────────────────────────────────────
sudo npm install -g n
sudo n 22
echo "✅ Node.js and n installed and version set successfully!"

# ──────────────────────────────────────────────────
# Docker
# ──────────────────────────────────────────────────
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

sudo apt update

docker_packages=(
    "docker-ce"
    "docker-ce-cli"
    "containerd.io"
    "docker-buildx-plugin"
    "docker-compose-plugin"
)

for package in "${docker_packages[@]}"; do
    sudo apt install -y "$package"
done

sudo systemctl enable docker
sudo systemctl start docker
echo "✅ Docker installed and started successfully!"

# ──────────────────────────────────────────────────
# Homebrew packages (CLI only — no casks / GUIs)
# ──────────────────────────────────────────────────
brew update

brew_packages=(
    "fzf"
    "xh"
    "doggo"
    "neovim"
    "tmux"
    "starship"
    "stow"
    "eza"
    "zoxide"
    "btop"
    "tlrc"
    "ripgrep"
    "zsh"
    "minikube"
    "kubectl"
    "helm"
    "git-delta"
    "angular-cli"
    "gitleaks"
    "rustfmt"
    "rust-analyzer"
    "go"
    "golangci-lint"
    "gofumpt"
    "superfile"
    "posting"
    "hashicorp/tap/terraform"
    "harlequin"
    "pass"
)

for package in "${brew_packages[@]}"; do
    if ! /home/linuxbrew/.linuxbrew/bin/brew install "$package"; then
        echo "❌ Error: Failed to install package '$package'"
        exit 1
    fi
done

echo "✅ Brew packages installed successfully!"

# ──────────────────────────────────────────────────
# Dotfiles
# ──────────────────────────────────────────────────

git clone https://github.com/junegunn/fzf-git.sh.git "$HOME/fzf-git.sh"
git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm/"

/home/linuxbrew/.linuxbrew/bin/stow --adopt -t "$HOME" home
echo "✅ Dotfiles stowed successfully!"

# ──────────────────────────────────────────────────
# Nix (devbox only — no GUI terminals or nixGL)
# ──────────────────────────────────────────────────
nix profile install nixpkgs#devbox
echo "✅ Devbox installed via nix!"

# ──────────────────────────────────────────────────
# Done
# ──────────────────────────────────────────────────
echo "🎉 WSL setup complete!"
