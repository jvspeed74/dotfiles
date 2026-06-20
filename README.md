# dotfiles

Personal environment config managed with [chezmoi](https://chezmoi.io). Works on Mac (Apple Silicon) and WSL Ubuntu.

## What's tracked

| Source file | Where it lands |
|---|---|
| `dot_zshrc` | `~/.zshrc` |
| `dot_gitconfig` | `~/.gitconfig` |
| `dot_config/nvim/` | `~/.config/nvim/` (LazyVim) |
| `dot_config/lazygit/` | `~/.config/lazygit/` |
| `dot_local/bin/` | `~/.local/bin/` (custom scripts, in PATH) |

`jetbrains/` and `install.sh` live in this repo but are **not** applied to home.

## Bootstrap a new machine

**Step 1 — Install chezmoi and pull your configs**

```bash
bash -c "$(curl -fsLS get.chezmoi.io)" -- init --apply jvspeed74
```

This downloads chezmoi, clones this repo, and applies all managed files to `~` in one shot.

**Step 2 — Run the install script** (Oh My Zsh, zsh plugins, uv)

```bash
bash ~/.local/share/chezmoi/install.sh
```

**Step 3 — Restart your shell**

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
