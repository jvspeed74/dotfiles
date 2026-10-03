#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Linux" ]]; then
    exit 0
fi

# `sudo -v` prompts unless credentials are cached or every matching sudoers rule is NOPASSWD.
sudo -n true 2>/dev/null || sudo -v
sudo apt-get update
# Non-interactive, keeping existing config files: a dependency upgrade must not stop at a dpkg
# conffile prompt.
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::=--force-confold \
    build-essential \
    unzip \
    golang-go \
    libnspr4 \
    libnss3 \
    libasound2t64 \
    python3-venv \
    zsh

# Ubuntu defaults to bash; without this, ~/.zshenv and ~/.zshrc are never read.
zsh_path="$(command -v zsh)"
if [[ "$(getent passwd "$USER" | cut -d: -f7)" != "$zsh_path" ]]; then
    sudo chsh -s "$zsh_path" "$USER"
fi

command -v go >/dev/null || { echo "golang-go install failed" >&2; exit 1; }
command -v unzip >/dev/null || { echo "unzip install failed" >&2; exit 1; }
gcc --version >/dev/null || { echo "build-essential (gcc) install failed" >&2; exit 1; }
command -v zsh >/dev/null || { echo "zsh install failed" >&2; exit 1; }
python3 -c 'import ensurepip' 2>/dev/null || { echo "python3-venv install failed (no ensurepip)" >&2; exit 1; }
[[ "$(getent passwd "$USER" | cut -d: -f7)" == "$zsh_path" ]] || { echo "chsh to zsh failed" >&2; exit 1; }
