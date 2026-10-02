# dotfiles

Personal environment config managed with [chezmoi](https://chezmoi.io). Works on Mac (Apple Silicon) and WSL Ubuntu.

## What's tracked

| Source file | Where it lands |
|---|---|
| `dot_zshenv.tmpl` | `~/.zshenv` (Homebrew on Linux, corporate proxy and CAs, cargo env, `EDITOR`, `DOTNET_ROOT`, `psql` on PATH) |
| `dot_zshrc.tmpl` | `~/.zshrc` |
| `dot_gitconfig.tmpl` | `~/.gitconfig` |
| `dot_npmrc.tmpl` | `~/.npmrc` |
| `dot_cargo/config.toml.tmpl` | `~/.cargo/config.toml` |
| `dot_config/nvim/create_lazyvim.json` | `~/.config/nvim/lazyvim.json` — LazyVim Extras seed, written only if missing |
| `dot_config/nvim/lua/plugins/sql.lua` | `~/.config/nvim/lua/plugins/sql.lua` — SQLFluff follows each project's `.sqlfluff` dialect |
| `dot_sqlfluff` | `~/.sqlfluff` — default SQL dialect (`ansi`) |
| `dot_config/lazygit/` | `~/.config/lazygit/` |
| `dot_local/bin/` | `~/.local/bin/` (custom scripts, in PATH) |

`jetbrains/` lives in this repo but is **not** applied to home.

## Tool inventory (auto-installed via `run_once_after_*` scripts)

| Tool | Script |
|---|---|
| Homebrew (Mac: `/opt/homebrew`; Linux: `/home/linuxbrew/.linuxbrew`, plus its apt prerequisites) | `run_once_after_05-install-homebrew.sh.tmpl` |
| build-essential, unzip, golang-go, headless-Chrome runtime libs, python3-venv (Mason's Python tools), zsh + `chsh` to it (Linux only) | `run_once_after_10-install-apt-packages.sh` |
| Rust (rustup/cargo) | `run_once_after_11-install-rustup.sh.tmpl` |
| Node.js LTS (nvm) | `run_once_after_12-install-nvm-node.sh.tmpl` |
| uv | `run_once_after_13-install-uv.sh.tmpl` |
| Oh My Zsh + zsh-autosuggestions + zsh-syntax-highlighting | `run_once_after_14-install-oh-my-zsh.sh.tmpl` |
| lazygit (brew) | `run_once_after_15-install-lazygit.sh.tmpl` |
| mermaid-cli + headless Chrome | `run_once_after_16-install-mermaid-cli.sh.tmpl` |
| gh (brew) | `run_once_after_17-install-gh.sh.tmpl` |
| ripgrep, fd (brew) | `run_once_after_18-install-ripgrep-fd.sh.tmpl` |
| Neovim, tree-sitter-cli, fzf (brew), JetBrainsMono Nerd Font (Mac cask), LazyVim starter + plugins | `run_once_after_19-install-neovim-lazyvim.sh.tmpl` |
| .NET SDK, psql (libpq), Snowflake CLI `snow` (brew) | `run_once_after_20-install-dev-clients.sh.tmpl` |

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

**After bootstrap:** run `gh auth login` once. `~/.gitconfig` routes GitHub HTTPS credentials
through `gh` (by absolute path, so GUI apps without your shell `PATH` work too); until you log in,
git falls back to prompting.

### Corporate WSL: before running the one-liner

The one-liner downloads chezmoi and clones this repo *before* any script runs, so on a
TLS-inspecting corporate proxy the CA cert and proxy must already be in place. In order:

1. **Confirm WSL2** — `wsl -l -v` in PowerShell must show `VERSION 2`.
2. **Use Ubuntu 24.04 or later** — the apt script installs `libasound2t64`, a package name that
   does not exist on 22.04.
3. **Mirrored networking, if the proxy is Windows-local** — if the proxy is an agent listening on
   `127.0.0.1` on the Windows host, WSL2's default NAT networking cannot reach it. Set
   `networkingMode=mirrored` in the Windows-side `%UserProfile%\.wslconfig` (no WSL-side script
   can configure this), then `wsl --shutdown`.
4. **Trust the corporate CA** (substitute your exported cert path):

   ```bash
   sudo cp /mnt/c/path/to/corp-root-ca.crt /usr/local/share/ca-certificates/corporate-root-ca.crt && sudo update-ca-certificates
   ```

   `run_onchange_before_00-import-ca-cert.sh.tmpl` repeats this idempotently later; it is needed here
   because the bootstrap download happens first.
5. **Export the proxy in the current (bash) shell** — both cases, since `curl` ignores uppercase
   `HTTP_PROXY`:

   ```bash
   export http_proxy=http://proxy.corp.example:8080 https_proxy=http://proxy.corp.example:8080 HTTP_PROXY=http://proxy.corp.example:8080 HTTPS_PROXY=http://proxy.corp.example:8080
   ```

6. **Run the one-liner above.**

After bootstrap, the proxy lives in `~/.zshenv`, which every zsh reads (including non-interactive
`wsl.exe <cmd>`). So does corporate CA trust for tools that ignore the system store: Node gets
`NODE_EXTRA_CA_CERTS` (the copy `before_00` installs on Linux; your exported cert path on Mac) and
uv gets `UV_SYSTEM_CERTS=1`. Homebrew downloads through the same proxy, so it must allow
`github.com` (installer, taps) and `ghcr.io` (bottles). `/etc/environment` is deliberately not used: WSL starts shells without a PAM
session, so `pam_env` never loads it
([microsoft/WSL#9213](https://github.com/microsoft/WSL/issues/9213)).

## Neovim (LazyVim)

`after_19` installs Neovim and bootstraps the [LazyVim starter](https://github.com/LazyVim/starter)
into `~/.config/nvim`, then pre-installs plugins (`nvim --headless "+Lazy! sync" +qa`). Language
servers, formatters, and treesitter parsers install on the first interactive launch.

- **Existing config is never touched.** If `~/.config/nvim` already contains files other than the
  two chezmoi manages, the bootstrap prints a warning and skips. To bootstrap later, move your
  config aside and run just that script (it is `run_once_`, so `chezmoi apply` will not repeat it):
  `chezmoi execute-template < "$(chezmoi source-path)/run_once_after_19-install-neovim-lazyvim.sh.tmpl" | bash`
- **Extras** come from `lazyvim.json`: rust, python, sql, json, yaml, toml, markdown, docker,
  dotnet, git, chezmoi, dot. The repo seeds it once; afterwards change Extras with `:LazyExtras`.
- **SQL dialects:** `~/.sqlfluff` sets `ansi`. Put a `.sqlfluff` in a project to switch it, e.g.
  `[sqlfluff]` / `dialect = postgres` (or `snowflake`). Postgres connections work in dadbod-ui via
  `psql`. Snowflake is via the `snow` CLI only — vim-dadbod's Snowflake adapter needs the legacy
  `snowsql`, which is not installed.
- **Nerd Font: JetBrainsMono Nerd Font.** On Mac it is installed automatically; select it in your
  terminal's font settings. On Windows (WSL), download `JetBrainsMono.zip` from the official
  [nerd-fonts releases](https://github.com/ryanoasis/nerd-fonts/releases), right-click the `.ttf`
  files → **Install** (current user, no admin), then choose **JetBrainsMono Nerd Font** in Windows
  Terminal → Ubuntu profile → Appearance → Font face. Avoid the winget package
  `DEVCOM.JetBrainsMonoNerdFont`: it is an unofficial repackaging that requires admin.
- **Corporate:** plugin clones, Mason downloads, and Homebrew all go through the proxy. Mason's
  Python tools use `PIP_CERT` (set in `~/.zshenv` on Linux) to trust the corporate CA.

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
