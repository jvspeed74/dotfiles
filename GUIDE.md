# Dotfiles guide

## How chezmoi works

chezmoi keeps a **source directory** (`~/.local/share/chezmoi/`) that mirrors your home directory structure. `chezmoi apply` copies files from source → `~`. `chezmoi add` goes the other direction: home → source.

The naming convention exists because git can't track dotfiles that start with `.` easily when you're also versioning the directory itself. chezmoi solves this by renaming:

- `dot_zshrc` in source → `.zshrc` in `~`
- `dot_config/nvim/` in source → `~/.config/nvim/`
- `dot_local/bin/` in source → `~/.local/bin/`

Files listed in `.chezmoiignore` (`install.sh`, `jetbrains/`, the markdown files) exist in the source repo but are never applied to `~`.

**Rule:** don't edit managed files directly in `~`. Use `chezmoi edit <file>` instead. If you do edit in `~` directly, run `chezmoi re-add` to pull those changes back into source before they get overwritten.

---

## Day-to-day workflow

### Editing a tracked config

```bash
chezmoi edit ~/.zshrc    # opens dot_zshrc in $EDITOR
chezmoi apply            # writes the change to ~/.zshrc
chezmoi cd               # cd to ~/.local/share/chezmoi/
git add -A && git commit -m "..." && git push
```

Or edit the source file directly if you prefer:

```bash
chezmoi cd
vim dot_zshrc
chezmoi apply
git add -A && git commit -m "..." && git push
```

### Syncing to another machine

```bash
chezmoi update
```

That's it. It runs `git pull` + `chezmoi apply` in one shot. Use this on your Mac after pushing from WSL (or vice versa).

---

## Tracking a new config file

When you install something new and it creates a config file you want to keep:

```bash
chezmoi add ~/.config/lazygit/config.yml
chezmoi cd
git add -A && git commit -m "Add lazygit config" && git push
```

chezmoi copies the file into source and handles the renaming automatically.

### Tracking a whole directory

```bash
chezmoi add ~/.config/nvim
```

Recursively adds everything under that directory. Do this when you've set up LazyVim and want to commit the full config.

---

## Adding scripts to PATH

`~/.local/bin/` is already in your PATH (set in `.zshrc`). Drop executables there and they're available everywhere.

### Shell script

```bash
cat > ~/.local/bin/my-script << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "hello"
EOF
chmod +x ~/.local/bin/my-script

chezmoi add ~/.local/bin/my-script
chezmoi cd && git add -A && git commit -m "Add my-script" && git push
```

### Python script with uv

Because you have `uv` on every machine, Python scripts can declare their own dependencies inline — no venv setup, no `requirements.txt` for standalone scripts.

```python
#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.12"
# dependencies = ["httpx", "rich"]
# ///

import httpx
from rich import print

response = httpx.get("https://example.com")
print(response.status_code)
```

Save to `~/.local/bin/my-script.py`, make it executable, then `chezmoi add`. uv installs the dependencies automatically on first run and caches them — subsequent runs are fast.

---

## OS-specific zsh config

Your `.zshrc` runs on both Mac and WSL. Use this pattern for anything platform-specific:

```zsh
if [[ "$(uname)" == "Darwin" ]]; then
    # Mac only
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif grep -qi microsoft /proc/version 2>/dev/null; then
    # WSL only
    export BROWSER=wslview
fi

# Everything below runs on both
```

Add that block to `.zshrc` via `chezmoi edit ~/.zshrc`.

---

## Troubleshooting

### `chezmoi` command not found

`~/.local/bin` isn't in PATH yet for this session. Either restart your shell, or:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

This is temporary — your managed `.zshrc` has the permanent fix, which takes effect on next shell start.

### `chezmoi diff` shows unexpected changes

You (or a tool) edited the file directly in `~` instead of through chezmoi.

- To keep the home version: `chezmoi re-add ~/.the/file`
- To revert home to what source says: `chezmoi apply`

### Changes on GitHub aren't showing up

`chezmoi apply` only reads local source. To also pull from GitHub first:

```bash
chezmoi update    # pull + apply
```

### You edited a file on Mac, want it on WSL (or vice versa)

On the machine where you made changes:
```bash
chezmoi cd && git add -A && git commit -m "..." && git push
```

On the other machine:
```bash
chezmoi update
```
