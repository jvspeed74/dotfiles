#!/usr/bin/env bash
set -euo pipefail

CHEZMOI="${HOME}/.local/bin/chezmoi"
ZSH_CUSTOM="${ZSH_CUSTOM:-${HOME}/.oh-my-zsh/custom}"
OS="$(uname -s)"

# Homebrew — Mac only
if [[ "$OS" == "Darwin" ]] && ! command -v brew &>/dev/null; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# uv
if ! command -v uv &>/dev/null && [[ ! -f "${HOME}/.local/bin/uv" ]]; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
fi
export PATH="${HOME}/.local/bin:${PATH}"

# Oh My Zsh
if [[ ! -d "${HOME}/.oh-my-zsh" ]]; then
    RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

# zsh plugins
clone_if_missing() {
    [[ ! -d "$2" ]] && git clone --depth=1 "$1" "$2"
}
clone_if_missing https://github.com/zsh-users/zsh-autosuggestions \
    "${ZSH_CUSTOM}/plugins/zsh-autosuggestions"
clone_if_missing https://github.com/zsh-users/zsh-syntax-highlighting \
    "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting"

# chezmoi
if ! command -v chezmoi &>/dev/null && [[ ! -f "${CHEZMOI}" ]]; then
    curl -fsLS get.chezmoi.io | sh -s -- -b "${HOME}/.local/bin"
fi

"${CHEZMOI}" apply --force

echo "Bootstrap complete. Restart your shell."
