#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Linux" ]]; then
    exit 0
fi

sudo -v
sudo apt-get update
sudo apt-get install -y \
    build-essential \
    ripgrep \
    fd-find \
    unzip \
    golang-go \
    libnspr4 \
    libnss3 \
    libasound2t64

mkdir -p "$HOME/.local/bin"
ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"

command -v rg >/dev/null || { echo "ripgrep install failed" >&2; exit 1; }
command -v fd >/dev/null || { echo "fd symlink failed" >&2; exit 1; }
command -v go >/dev/null || { echo "golang-go install failed" >&2; exit 1; }
command -v unzip >/dev/null || { echo "unzip install failed" >&2; exit 1; }
gcc --version >/dev/null || { echo "build-essential (gcc) install failed" >&2; exit 1; }
