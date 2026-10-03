# dotfiles

[chezmoi](https://chezmoi.io)-managed configuration and tool setup for macOS (Apple Silicon;
bootstrap not CI-tested) and WSL2 Ubuntu 24.04 or 26.04, on personal machines or behind a
TLS-inspecting corporate proxy.

## Quick start

**Personal machine**, in a real terminal:

```bash
bash -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin" init --apply jvspeed74
```

The repo is private: git asks for credentials during the clone
([clone the private repo](GUIDE.md#clone-the-private-repo)). On a fresh Mac, run
`xcode-select --install` first.

**Machine already has dotfiles?** Use [existing machine](GUIDE.md#existing-machine): the one-liner
overwrites them without asking.

**Corporate WSL machine:** do the [corporate WSL preconditions](GUIDE.md#corporate-wsl-preconditions)
first; the one-liner needs the proxy and CA before any of this repo runs.

## What you get

| Area | Contents |
|---|---|
| Shell | zsh as login shell, Oh My Zsh with autosuggestions and syntax highlighting |
| CLI tools | Homebrew, gh, lazygit, ripgrep, fd, fzf |
| Languages | Rust (rustup), Node LTS (nvm), Python tooling (uv), .NET SDK, Go (Linux) |
| Editor | Neovim with LazyVim and 12 Extras, JetBrainsMono Nerd Font on macOS |
| Data | `psql`, Snowflake CLI (`snow`), dialect-aware SQL lint and format |
| Diagrams | mermaid-cli |
| Corporate | Proxy and CA trust for apt, git, npm, cargo, Node, uv, Homebrew; telemetry off |

Per-script details: [ARCHITECTURE layer 4](ARCHITECTURE.md#4-provisioning-scripts).

## Docs

| Doc | Read it when | You'll find |
|---|---|---|
| [GUIDE.md](GUIDE.md) | You use a machine set up from this repo | Setup, everyday tasks, Neovim, corporate machines, troubleshooting |
| [ARCHITECTURE.md](ARCHITECTURE.md) | You want to know how it works | The eight layers, start to finish, with diagrams and failure modes |
| [CONTRIBUTING.md](CONTRIBUTING.md) | You change this repo | Rules, local testing, CI, and step-by-step recipes |
