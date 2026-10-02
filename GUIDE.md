# Guide

Tasks for the person using a machine set up from this repo. Each task: **When** → **Steps** →
**Check**. How it works underneath is in [ARCHITECTURE.md](ARCHITECTURE.md).

## Set up a machine

### Personal machine

**When:** a Mac (Apple Silicon) or WSL2 Ubuntu 24.04 machine with no corporate proxy.

**Steps**

1. Open a real terminal (the bootstrap prompts and calls `sudo`).
2. Run:

   ```bash
   bash -c "$(curl -fsLS get.chezmoi.io)" -- init --apply jvspeed74
   ```

3. Supply GitHub credentials when git asks ([clone the private repo](#clone-the-private-repo)).
4. Answer `false` to "Is this a corporate-managed machine".
5. Do the steps in [after bootstrap](#after-bootstrap).

**Check:** a new terminal opens zsh with Oh My Zsh, and `chezmoi status` prints nothing.

### Clone the private repo

**When:** always; the repo is private, so the clone in the one-liner needs credentials.

**Steps**, one of:

| Method | How | Notes |
|---|---|---|
| HTTPS + token | Create a [fine-grained personal access token](https://github.com/settings/personal-access-tokens) with read access to *Contents* of `jvspeed74/dotfiles`. When git prompts, enter your GitHub username and paste the token as the password. | Works behind corporate proxies. git does not store it; `chezmoi update` asks again until [`gh auth login`](#after-bootstrap). |
| SSH | Replace `jvspeed74` in the one-liner with `git@github.com:jvspeed74/dotfiles.git`. | Needs an SSH key already registered with GitHub. Corporate networks often block port 22. |

**Check:** `chezmoi source-path` prints a directory that contains this repo.

### Corporate WSL preconditions

**When:** a WSL2 machine behind a TLS-inspecting corporate proxy. Do these **before** the one-liner:
it downloads chezmoi and clones the repo before any repo script runs.

**Steps**

1. Confirm WSL2: `wsl -l -v` in PowerShell shows `VERSION 2`.
2. Use Ubuntu 24.04 or later (the apt script installs `libasound2t64`, which 22.04 lacks).
3. If the proxy listens on `127.0.0.1` on the Windows host, set `networkingMode=mirrored` in
   `%UserProfile%\.wslconfig`, then run `wsl --shutdown`. WSL2's default NAT cannot reach it.
4. Export the corporate root CA from the Windows certificate store to a path under `/mnt/c/…`, then
   trust it in Ubuntu:

   ```bash
   sudo cp /mnt/c/path/to/corp-root-ca.crt /usr/local/share/ca-certificates/corporate-root-ca.crt && sudo update-ca-certificates
   ```

5. Export the proxy in the current shell, in both cases (`curl` ignores uppercase `HTTP_PROXY`):

   ```bash
   export http_proxy=http://proxy.corp.example:8080 https_proxy=http://proxy.corp.example:8080 HTTP_PROXY=http://proxy.corp.example:8080 HTTPS_PROXY=http://proxy.corp.example:8080
   ```

6. Run the one-liner from [personal machine](#personal-machine) using the HTTPS + token method.
   Answer `true` to the corporate question, then give the proxy URL and the CA path from step 4.

**Check:** `env | grep -i proxy` in a new terminal shows four variables.

### After bootstrap

**When:** once, right after the first successful bootstrap.

**Steps**

1. Open a new terminal (the login shell is now zsh).
2. Run `gh auth login`. Git uses `gh` for GitHub HTTPS credentials; until you log in, git prompts.
3. Select the Nerd Font in your terminal ([install the Nerd Font](#install-the-nerd-font)).

**Check:** `gh auth status` shows you logged in.

## Everyday tasks

### Edit a managed file

**When:** changing any file this repo manages (`~/.zshrc`, `~/.gitconfig`, …).

**Steps**

1. `chezmoi edit ~/.zshrc` (opens the source file).
2. `chezmoi apply`.
3. `chezmoi cd`, then commit and push.

**Check:** `chezmoi diff` prints nothing.

### Sync another machine

**When:** you pushed changes from one machine and want them on another.

**Steps**

1. On the other machine: `chezmoi update` (`git pull` plus `chezmoi apply`).

**Check:** `chezmoi status` prints nothing.

### Track a new file or directory

**When:** a new config file in `~` should follow you to every machine.

**Steps**

1. `chezmoi add ~/.config/lazygit/config.yml` (a directory works too).
2. `chezmoi cd`, then commit and push.

**Check:** the file appears in the source state with chezmoi's naming (`dot_config/…`).

For files that differ per OS or per corporate/personal, see
[CONTRIBUTING R3](CONTRIBUTING.md#r3-track-a-new-dotfile).

### Add a script to your PATH

**When:** a personal command should exist on every machine. `~/.local/bin` is first on PATH.

**Steps**

1. Write it to `~/.local/bin/<name>` and `chmod +x` it. For Python, uv can resolve dependencies
   inline, with no virtualenv:

   ```python
   #!/usr/bin/env -S uv run
   # /// script
   # requires-python = ">=3.12"
   # dependencies = ["httpx"]
   # ///
   import httpx
   print(httpx.get("https://example.com").status_code)
   ```

2. `chezmoi add ~/.local/bin/<name>`, then commit and push.

**Check:** `command -v <name>` in a new terminal prints `~/.local/bin/<name>`.

## Neovim

### First launch

**When:** the first time you run `nvim` on a machine.

**Steps**

1. Run `nvim` and wait: language servers, formatters, and syntax parsers download and build now
   (plugins were installed during bootstrap).
2. Run `:LazyHealth` and fix anything marked as an error.

**Check:** opening a `.py` or `.rs` file shows diagnostics.

### Change LazyVim Extras

**When:** you want more or fewer language packs or tools.

**Steps**

1. On this machine: `:LazyExtras`, toggle, restart Neovim.
2. For future machines: edit `dot_config/nvim/create_lazyvim.json`
   ([CONTRIBUTING R9](CONTRIBUTING.md#r9-change-the-lazyvim-extras-seed)).

**Check:** `~/.config/nvim/lazyvim.json` lists the Extras you expect.

Enabled by default: rust, python, sql, json, yaml, toml, markdown, docker, dotnet, git, chezmoi, dot.

### Set a SQL dialect per project

**When:** a project's SQL is Postgres or Snowflake rather than ANSI.

**Steps**

1. Add `.sqlfluff` to the project root:

   ```ini
   [sqlfluff]
   dialect = postgres
   ```

   Use `snowflake` for Snowflake. Without this file, `~/.sqlfluff` applies `ansi`.

**Check:** formatting a `.sql` file no longer flags dialect-specific syntax.

### Connect to databases

**When:** querying a database from Neovim or the terminal.

| Database | How |
|---|---|
| Postgres | In Neovim, open dadbod-ui and add a connection URL such as `postgresql://user@host/db`; it uses `psql`. |
| Snowflake | Terminal only, with the `snow` CLI (`snow connection add`, then `snow sql`). Neovim's dadbod needs the legacy `snowsql`, which is not installed. |

### Install the Nerd Font

**When:** icons in Neovim show as boxes or question marks.

| Where `nvim` runs | Steps |
|---|---|
| macOS terminal | Already installed (JetBrainsMono Nerd Font). Select it in the terminal's font settings. |
| WSL in Windows Terminal | Download `JetBrainsMono.zip` from the official [nerd-fonts releases](https://github.com/ryanoasis/nerd-fonts/releases), right-click the `.ttf` files and choose **Install** (current user, no admin), then pick **JetBrainsMono Nerd Font** in Windows Terminal → Ubuntu profile → Appearance → Font face. |

Avoid the winget package `DEVCOM.JetBrainsMonoNerdFont`: it is an unofficial repackaging that
requires admin.

### Re-run the LazyVim bootstrap

**When:** the bootstrap printed "already has a config; skipping" and you now want LazyVim.

**Steps**

1. `mv ~/.config/nvim ~/.config/nvim.bak`
2. `chezmoi apply` (restores the two managed files).
3. Run the bootstrap script directly; it is `run_once_`, so `chezmoi apply` will not repeat it:

   ```bash
   chezmoi execute-template < "$(chezmoi source-path)/run_once_after_19-install-neovim-lazyvim.sh.tmpl" | bash
   ```

**Check:** `~/.config/nvim/lua/config/lazy.lua` exists.

## Corporate machines

### Switch a personal machine to corporate

**When:** a machine set up as personal moves behind the corporate proxy.

**Steps**

1. Edit `~/.config/chezmoi/chezmoi.toml`: set `is_corporate = true`, and fill in
   `corporate_proxy_url` and `corporate_ca_cert_source_path`. (`chezmoi init` will not ask again:
   the keys already exist.)
2. `chezmoi apply`. The CA and apt-proxy scripts run, and install scripts whose content changed
   re-run once.

**Check:** `env | grep -i proxy` in a new terminal shows four variables.

### What is configured for you

Proxy settings, CA trust per tool, and telemetry opt-outs are listed in
[ARCHITECTURE layer 6](ARCHITECTURE.md#6-corporate-network), together with known gaps.

## JetBrains settings

JetBrains Sync stays off: syncing PyCharm, Rider, and RustRover overwrites one IDE's settings with
another's.

| Task | Steps |
|---|---|
| Export | File → Manage IDE Settings → Export Settings → save the zip to `jetbrains/` in this repo, then commit. |
| Import | File → Manage IDE Settings → Import Settings → pick that IDE's zip. |

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `chezmoi: command not found` right after bootstrap | The installer put `chezmoi` in `./bin` of the directory you ran it from; `~/bin` is on PATH only in new zsh terminals | Open a new terminal, or run `./bin/chezmoi`; if you ran the one-liner elsewhere, move `bin/chezmoi` to `~/.local/bin`. |
| `chezmoi diff` shows changes you did not make in source | A target in `~` was edited directly | Keep the edit: `chezmoi re-add <file>`. Discard it: `chezmoi apply`. |
| Changes pushed from another machine are missing | `chezmoi apply` reads only the local source | `chezmoi update` |
| git asks for a GitHub username or password | Not logged in to `gh` | `gh auth login` |
| A command works in a terminal but not through `wsl.exe <cmd>` | Its setup is only in `~/.zshrc` | See [ARCHITECTURE layer 5](ARCHITECTURE.md#5-shell-environment). |
| The same install script runs on every `chezmoi apply` | Its self-check keeps failing | Read the script's error output in the `chezmoi apply` log. |
| Neovim icons show as boxes | No Nerd Font selected | [Install the Nerd Font](#install-the-nerd-font) |
