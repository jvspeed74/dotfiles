# dotfiles

Personal environment config managed with [chezmoi](https://chezmoi.io). Works on Mac (Apple Silicon) and WSL Ubuntu.

## What's tracked

| Source file | Where it lands |
|---|---|
| `dot_zshrc.tmpl` | `~/.zshrc` |
| `dot_gitconfig.tmpl` | `~/.gitconfig` |
| `dot_npmrc.tmpl` | `~/.npmrc` |
| `dot_cargo/config.toml.tmpl` | `~/.cargo/config.toml` |
| `dot_config/nvim/` | `~/.config/nvim/` (LazyVim) |
| `dot_config/lazygit/` | `~/.config/lazygit/` |
| `dot_local/bin/` | `~/.local/bin/` (custom scripts, in PATH) |

`jetbrains/` lives in this repo but is **not** applied to home.

## Tool inventory (auto-installed via `run_once_after_*` scripts)

| Tool | Script |
|---|---|
| Homebrew (Mac only) | `run_once_after_05-install-homebrew.sh.tmpl` |
| build-essential, ripgrep, fd, unzip, golang-go, headless-Chrome runtime libs (Linux only) | `run_once_after_10-install-apt-packages.sh` |
| Rust (rustup/cargo) | `run_once_after_11-install-rustup.sh.tmpl` |
| Node.js LTS (nvm) | `run_once_after_12-install-nvm-node.sh.tmpl` |
| uv | `run_once_after_13-install-uv.sh.tmpl` |
| Oh My Zsh + zsh-autosuggestions + zsh-syntax-highlighting | `run_once_after_14-install-oh-my-zsh.sh.tmpl` |
| lazygit (brew on Mac, built from source on Linux — not in apt) | `run_once_after_15-build-lazygit.sh.tmpl` |
| mermaid-cli + headless Chrome | `run_once_after_16-install-mermaid-cli.sh.tmpl` |

Each runs once (chezmoi tracks a content hash) and self-checks that the tool actually works
before exiting successfully.

## Bootstrap a new machine

**One step:**

```bash
bash -c "$(curl -fsLS get.chezmoi.io)" -- init --apply jvspeed74
```

This downloads chezmoi, clones this repo, applies all managed files to `~`, and runs every
tool-install script above, in order — no second script to run manually anymore.

**Must run in a real interactive terminal** — not backgrounded, piped, or run from cron/CI.
Several steps prompt for your sudo password (importing a corporate CA cert, apt package
installs), and a non-interactive invocation will hang or fail rather than prompt.

You'll be asked:

- **"Is this a corporate-managed machine?"** — answer `false` on a personal machine and every
  corporate-specific step below becomes a clean no-op. Answer `true` on a corporate machine and
  you'll be asked two more questions:
  - **Corporate proxy URL** — used to configure apt, git, npm, cargo, and your shell's
    `HTTP_PROXY`/`HTTPS_PROXY`.
  - **Path to your exported corporate root CA cert** — **export this from the Windows cert
    store to a path reachable from WSL (e.g. under `/mnt/c/...`) *before* running `chezmoi init`**,
    since this prompt happens during init, not after.

These answers are stored locally in `~/.config/chezmoi/chezmoi.toml` — never committed to this
repo.

**Not covered here:** WSL2 "mirrored networking mode" is a Windows-host `.wslconfig` setting
(`networkingMode=mirrored`), not something any WSL-side script can configure. Set it manually if
needed, then `wsl --shutdown` to apply it.

## Quick reference

```bash
chezmoi diff                     # see what's out of sync between source and home
chezmoi apply                    # push source → home
chezmoi add ~/.some/file         # start tracking a new file
chezmoi edit ~/.zshrc            # edit a tracked file (opens in $EDITOR)
chezmoi update                   # git pull + apply in one command (use on secondary machines)
chezmoi cd                       # jump into the source directory
```

After making changes in the source directory: commit and push like any git repo.

## JetBrains

JetBrains Sync is intentionally disabled — syncing across different IDEs (PyCharm, Rider, RustRover) causes settings from one IDE to overwrite incompatible settings in another.

**Export:** File → Manage IDE Settings → Export Settings → save zip to `jetbrains/` in this repo.  
**Import on a new machine:** File → Manage IDE Settings → Import Settings → pick the zip for that IDE.

```
jetbrains/
├── PyCharm_settings.zip
├── Rider_settings.zip
└── RustRover_settings.zip
```
