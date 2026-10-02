# Dotfiles guide

## How chezmoi works

chezmoi keeps a **source directory** (`~/.local/share/chezmoi/`) that mirrors your home directory structure. `chezmoi apply` copies files from source → `~`. `chezmoi add` goes the other direction: home → source.

The naming convention exists because git can't track dotfiles that start with `.` easily when you're also versioning the directory itself. chezmoi solves this by renaming:

- `dot_zshrc.tmpl` in source → `.zshrc` in `~`
- `dot_config/nvim/` in source → `~/.config/nvim/`
- `dot_local/bin/` in source → `~/.local/bin/`

A `.tmpl` suffix (e.g. `dot_zshrc.tmpl`, `dot_gitconfig.tmpl`) means the file is processed as a
Go template before being written to `~` — used here for the `{{ if .is_corporate }}` conditional
blocks (see "Corporate-environment config" below).

Files listed in `.chezmoiignore` (`jetbrains/`, the markdown files) exist in the source repo but are never applied to `~`.

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

`dot_zshrc.tmpl` runs on both Mac and WSL. Since it's a template now, prefer chezmoi's
template-time OS detection over a runtime `uname` check:

```zsh
{{ if eq .chezmoi.os "darwin" -}}
# Mac only
eval "$(/opt/homebrew/bin/brew shellenv)"
{{ else if .chezmoi.kernel.osrelease | lower | contains "microsoft" -}}
# WSL only
export BROWSER=wslview
{{ end -}}

# Everything below runs on both
```

Add that block via `chezmoi edit ~/.zshrc`. This resolves once, when chezmoi applies the file,
rather than every shell startup — slightly faster, and consistent with how the corporate proxy
block already works in this file.

---

## Scripts: `run_once_`, `run_onchange_`, and the `before_`/`after_` ordering gotcha

Tool installs (rustup, nvm, uv, apt packages, etc.) and corporate system setup (CA cert import,
apt proxy config) live as chezmoi scripts, not a separate `install.sh` — see the
[README's tool inventory](README.md#tool-inventory-auto-installed-via-run_once_after_-scripts).

**Naming:** `run_[once_|onchange_][before_|after_]<name>.sh[.tmpl]`

- `run_once_` — runs once ever (chezmoi hashes the rendered content; never reruns after success).
  Used for tool installs: installing rustup twice is pointless, not harmful, so "once" is right.
- `run_onchange_` — reruns automatically whenever its *rendered* content changes. Used for the
  two corporate-config scripts: if the proxy URL rotates or `is_corporate` changes, the template
  output differs, and chezmoi treats that as new content to run.
- `before_` / `after_` — controls execution relative to file application: `before_` scripts run
  first, `after_` scripts run after every managed file (`dot_*`) is already on disk.

**The gotcha:** scripts execute in alphabetical order of their *full filename*. Comparing the
literal strings `run_once_` and `run_onchange_`, they diverge at `e` (once) vs `h` (onchange) —
and `e` sorts before `h`. That means **every `run_once_` script alphabetically precedes every
`run_onchange_` script, regardless of any numeric prefix you add.** A numeric prefix alone
(`run_onchange_00-x.sh`, `run_once_10-y.sh`) will NOT force the onchange script to run first.

This is why the corporate CA-cert and apt-proxy scripts are explicitly named
`run_onchange_before_00-...` / `run_onchange_before_01-...` — the `before_` infix forces them to
run before *any* `after_` script, sidestepping the once/onchange sort order entirely. If you add
a new script, always include `before_` or `after_` explicitly rather than relying on numeric
prefixes to control phase ordering.

---

## Corporate-environment config

`chezmoi init` asks once whether this is a corporate-managed machine (`is_corporate`), storing
the answer — and, if true, a proxy URL and CA cert path — in the local, uncommitted
`~/.config/chezmoi/chezmoi.toml`. Every corporate-conditional file/script reads from that same
data via `{{ if .is_corporate }}`.

If you later move an already-initialized personal machine to a corporate network (flipping
`is_corporate` from false to true), `chezmoi init` won't automatically re-prompt for the proxy
URL and cert path — those keys already exist (as empty strings) from the first run, and
chezmoi's `promptStringOnce`/`promptBoolOnce` only prompt when a key is *absent*. Work around
this by editing `~/.config/chezmoi/chezmoi.toml` directly (set `is_corporate = true` and fill in
the two string values, or delete the file entirely) before the next `chezmoi apply`.

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
