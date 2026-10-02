#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Linux" ]]; then
    exit 0
fi

sudo -v
sudo apt-get update
sudo apt-get install -y \
    build-essential \
    unzip \
    golang-go \
    libnspr4 \
    libnss3 \
    libasound2t64 \
    python3-venv \
    zsh

# rg, fd, and gh now come from Homebrew (after_17, after_18). Remove the fd -> fdfind symlink an
# earlier version created; ~/.local/bin precedes Homebrew in PATH and would shadow brew's fd.
if [[ -L "$HOME/.local/bin/fd" && "$(readlink "$HOME/.local/bin/fd")" == *fdfind ]]; then
    rm "$HOME/.local/bin/fd"
fi

# Ubuntu defaults to bash; without this, ~/.zshenv and ~/.zshrc are never read.
zsh_path="$(command -v zsh)"
if [[ "$(getent passwd "$USER" | cut -d: -f7)" != "$zsh_path" ]]; then
    sudo chsh -s "$zsh_path" "$USER"
fi

command -v go >/dev/null || { echo "golang-go install failed" >&2; exit 1; }
command -v unzip >/dev/null || { echo "unzip install failed" >&2; exit 1; }
gcc --version >/dev/null || { echo "build-essential (gcc) install failed" >&2; exit 1; }
command -v zsh >/dev/null || { echo "zsh install failed" >&2; exit 1; }
python3 -m venv --help >/dev/null || { echo "python3-venv install failed" >&2; exit 1; }
[[ "$(getent passwd "$USER" | cut -d: -f7)" == "$zsh_path" ]] || { echo "chsh to zsh failed" >&2; exit 1; }
