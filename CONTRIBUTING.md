# Contributing

How to change this repo without breaking a machine that applies it. Read the rules, find your change
in [Recipes](#recipes), then [test locally](#test-locally). Background for every rule is in
[ARCHITECTURE.md](ARCHITECTURE.md).

## Rules that keep machines working

| Rule | Why |
|---|---|
| Name every script `run_once_after_NN-…` or `run_onchange_before_NN-…`, with an explicit `before_`/`after_`. | The infix sets the phase; `NN` sets the order within it ([layer 3](ARCHITECTURE.md#3-apply-engine-and-ordering)). |
| End every install script with a check that the tool runs, and `exit 1` if it does not. | A failed `run_once_` script is retried on the next apply; a silent failure never is. |
| Make every script idempotent. | Any change to a script's rendered content re-runs it on every machine already provisioned. |
| Evaluate `brew shellenv` in every script that calls `brew` (macOS only; Linux never uses Homebrew). | Scripts run in separate `bash` processes; nothing exported by `after_05` reaches them. |
| On Linux, install CLI tools from a pinned release with `install_release`, apt or PyPI, never Homebrew. The one exception is Claude Code (`after_21`), which uses its native installer and updates itself. | The corporate proxy blocks `ghcr.io` and `raw.githubusercontent.com`, which Homebrew needs ([layer 4](ARCHITECTURE.md#4-provisioning-scripts)). Claude Code is not a GitHub release, and `install_release` would bypass its launcher and auto-update. |
| Add PATH entries with `_dotfiles_path_prepend <dir>…` (defined in `dot_zshenv.tmpl`), never `export PATH=`. The one exception is the macOS login-shell line in `dot_zshrc.tmpl`, which prepends unconditionally after `path_helper` ([layer 5](ARCHITECTURE.md#5-shell-environment)). | It skips directories already on PATH, so a nested shell keeps its parent's order (an activated venv stays first) ([layer 5](ARCHITECTURE.md#5-shell-environment)). |
| Put variables that non-interactive commands need in `dot_zshenv.tmpl`, not `dot_zshrc.tmpl`. | `zsh -c` and `wsl.exe <cmd>` never read `~/.zshrc` ([layer 5](ARCHITECTURE.md#5-shell-environment)). |
| Wrap corporate-only content in `{{ if .is_corporate }}`. | Personal machines must render none of it ([layer 2](ARCHITECTURE.md#2-config-data-and-templating)). |
| Build OS-dependent paths from a `.chezmoitemplates/` partial. | One place to change per OS, instead of a path copied into many files. |
| Never let an installer edit a chezmoi-managed file. | The edit shows as drift and is reverted on the next apply ([layer 4](ARCHITECTURE.md#4-provisioning-scripts)). |
| Fetch tools with `git clone` from github.com or from a release download, not from `raw.githubusercontent.com`. | The corporate proxy blocks `raw.githubusercontent.com` (and `ghcr.io`); the corporate CI job blocks both too. Only macOS's `after_05` (Homebrew) uses it. |
| Add any new file under `dot_config/nvim/` to `managed_re` in `run_once_after_19-install-neovim-lazyvim.sh.tmpl`. | Otherwise fresh machines treat it as a user config and skip the LazyVim bootstrap. |
| Edit source files, not targets in `~`. | `chezmoi apply` overwrites targets from source. |
| Start every script with `#!/usr/bin/env bash` and `set -euo pipefail`. | A failing command must stop the script, so its self-check never reports a half-install as success. |
| Commit LF line endings; `.gitattributes` enforces it. | A CR in a `run_*` script breaks `bash`, and a CR in a skill's frontmatter can break its parsing. |
| Under `~/.claude`, manage only user-authored files (`CLAUDE.md`, `agents/`, skills), never with `exact_`, and never settings or state. | Claude Code rewrites its own files there, and `skills/synced` is managed by claude.ai. |
| Never wait for input: `apt-get -y` (with `DEBIAN_FRONTEND=noninteractive` and `--force-confold` where a dependency upgrade could hit a conffile prompt), `NONINTERACTIVE=1` for Homebrew; only `sudo` may prompt. | Any other prompt hangs the bootstrap. |

## Repo map

| Path | Role | Layer |
|---|---|---|
| `.chezmoi.toml.tmpl` | `init` prompts; per-machine data | [2](ARCHITECTURE.md#2-config-data-and-templating) |
| `.chezmoidata/linux-tools.toml` | Linux tool pins (release tag, asset, sha256) | [2](ARCHITECTURE.md#2-config-data-and-templating) |
| `.chezmoitemplates/` | Partials: `brew-prefix` (macOS), `gh-path`, `install-release`, `install-release-call` | [2](ARCHITECTURE.md#2-config-data-and-templating) |
| `.chezmoiignore` | Repo files never applied to `~` (docs, `jetbrains/`) | [3](ARCHITECTURE.md#3-apply-engine-and-ordering) |
| `run_onchange_before_00-import-ca-cert.sh.tmpl`, `run_onchange_before_01-configure-apt-proxy.sh.tmpl` | Corporate CA and apt proxy | [6](ARCHITECTURE.md#6-corporate-network) |
| `run_once_after_05-…` to `run_once_after_21-…` | Tool installs | [4](ARCHITECTURE.md#4-provisioning-scripts) |
| `private_dot_claude/` | `~/.claude` (mode 700): `CLAUDE.md` template, `agents/`, authored skills | [4](ARCHITECTURE.md#4-provisioning-scripts) |
| `.gitattributes` | Pins LF line endings; never applied to `~` | — |
| `dot_zshenv.tmpl`, `dot_zshrc.tmpl` | Shell environment | [5](ARCHITECTURE.md#5-shell-environment) |
| `dot_gitconfig.tmpl`, `dot_npmrc.tmpl`, `dot_cargo/config.toml.tmpl` | Tool configs (credential helper, corporate proxy) | [6](ARCHITECTURE.md#6-corporate-network) |
| `dot_config/nvim/`, `dot_sqlfluff` | LazyVim seed and SQL dialect override | [7](ARCHITECTURE.md#7-editor-neovim-and-lazyvim) |
| `.github/workflows/bootstrap.yml`, `.github/ci/` | CI | [8](ARCHITECTURE.md#8-verification-ci) |
| `jetbrains/` | IDE settings exports; not applied | — |

## Where to work

Develop in a separate clone, not in the chezmoi source directory:

```bash
git clone git@github.com:jvspeed74/dotfiles.git ~/src/dotfiles
```

| Step | Command |
|---|---|
| Preview your change against this machine's home | `chezmoi diff --source ~/src/dotfiles` |
| Test it | [Test locally](#test-locally) (Docker) |
| Roll it out after merging | `chezmoi update` on each machine |

**Pitfall:** editing in `chezmoi cd` and then running `chezmoi apply` puts an untested change on
your own machine.

## Test locally

All commands run from the repo root. Docker is required.

**Template checks** (about 1 minute; the same as the CI `templates` job):

```bash
docker run --rm -v "$PWD:/src:ro" ubuntu:24.04 bash -c 'apt-get update -qq && apt-get install -y -qq --no-install-recommends ca-certificates curl git >/dev/null && sh -c "$(curl -fsLS get.chezmoi.io)" -- -b /usr/local/bin && /src/.github/ci/templates.sh'
```

**Full bootstrap** in a fresh container, personal or behind the TLS-intercepting proxy. It runs as
x86_64, which is emulated and slow on Apple Silicon; CI runs it natively.

```bash
.github/ci/run-bootstrap.sh personal
```

```bash
.github/ci/run-bootstrap.sh corporate
```

Both default to `ubuntu:24.04`. CI also runs every job in `ubuntu:26.04`; to match it, prefix
either command with `UBUNTU_VERSION=26.04`. The test user is in group `sudo` with a NOPASSWD rule,
so a bare `sudo -v` in a `run_*` script fails there; use `sudo -n true 2>/dev/null || sudo -v`.

**Docs checks**: renders every Mermaid diagram and checks links, anchors, and backticked repo paths:

```bash
.github/ci/docs.sh
```

## CI

The jobs, which workflow runs them, and what each proves are in
[ARCHITECTURE layer 8](ARCHITECTURE.md#8-verification-ci). A docs-only change runs only `docs.yml`.
Never add a download cache to `bootstrap-corporate`: a cache hit skips the proxy and CA path the
job exists to test.

Reading a failure:

| Job | Where to look |
|---|---|
| `templates`, `bootstrap-*` | Lines starting `FAIL  `. The label names the area, e.g. `nvim: …`, `#5 …` (the PR that added it). |
| `bootstrap-corporate` | After a failure the job prints the proxy log tail. A `Client TLS handshake failed` line names the host whose client does not trust the corporate CA; a missing host means the client ignored the proxy. |
| `bootstrap-*`, before the checks | `chezmoi: <script>: exit status 1` names the install script whose self-check failed. |
| `docs` | `file:line` of the diagram that failed to render, or of the broken link or path. |

## Recipes

Each recipe: **Use when** → **Steps** → **Verify** → **Pitfall**.

### R1. Add a CLI tool

**Use when:** a tool should exist on every machine: Homebrew on macOS, a GitHub release on Linux.

**Steps**

1. Pin the Linux release in `.chezmoidata/linux-tools.toml`: `repo`, `tag`, `asset` (the
   `x86_64`/`amd64` Linux archive, `.tar.gz` or a single-file `.gz`), `sha256` and `bins` (paths
   inside the archive to link into `~/.local/bin`). Take `sha256` from the project's published
   checksums; if it publishes none, download the asset and record `sha256sum` (say so in the
   file's comment).
2. Create `run_once_after_NN-install-<tool>.sh.tmpl` with the next free `NN`:

   ```bash
   #!/usr/bin/env bash
   set -euo pipefail

   {{ if .is_corporate -}}
   export HTTP_PROXY={{ .corporate_proxy_url | quote }}
   export HTTPS_PROXY={{ .corporate_proxy_url | quote }}
   {{ end -}}

   {{ if eq .chezmoi.os "darwin" -}}
   eval "$({{ template "brew-prefix" . }}/bin/brew shellenv)"
   brew install <formula>
   {{ else -}}
   {{ template "install-release" . }}
   {{ template "install-release-call" (dict "name" "<tool>" "tool" .linuxTools.<key>) }}
   export PATH="$HOME/.local/bin:$PATH"
   {{ end -}}

   <tool> --version >/dev/null || { echo "<tool> not runnable after install" >&2; exit 1; }
   ```

3. Add a row to the script table in [ARCHITECTURE layer 4](ARCHITECTURE.md#4-provisioning-scripts)
   and the tool to README's "What you get".
4. In `.github/ci/templates.sh`, add `<tool>:<key>:<script>` to `release_tools` (it checks the
   sha256 and the rendered call) and, for macOS, a `brew install <formula>` check.
5. In `.github/ci/in-container.sh`, add `<tool>` to the `for tool in …` release loop.

**Verify:** template checks locally; both bootstrap jobs in CI. The corporate job blocks
`raw.githubusercontent.com` and `ghcr.io`, so a Linux path that needs them fails there.

**Pitfall:** a script without `export PATH="$HOME/.local/bin:$PATH"` on Linux. Its self-check
passes where `~/.local/bin` is already on the parent's PATH and fails on fresh machines.

### R2. Add a Linux-only apt package

**Use when:** the package is a system library or only needed on Linux.

**Steps**

1. Add it to the `apt-get install -y` list in `run_once_after_10-install-apt-packages.sh`.
2. Add a self-check line at the end of that script.

**Verify:** `bootstrap-personal`.

**Pitfall:** checking something the package does not provide. `python3 -m venv --help` passes even
without `python3-venv`; the real check is `import ensurepip`.

### R3. Track a new dotfile

**Use when:** a config file in `~` should be the same on every machine.

**Steps**

1. `chezmoi add ~/.example` (creates `dot_example` in the source state).
2. If it differs by OS or by corporate/personal: `chezmoi chattr +template ~/.example`, then add
   `{{ if eq .chezmoi.os "darwin" }}` or `{{ if .is_corporate }}` blocks.
3. Commit from `chezmoi cd`.

**Verify:** `chezmoi diff` on each machine type; the template checks render both profiles.

**Pitfall:** adding a file that an installer also writes to: every run then shows drift.

### R4. Add a corporate-only setting

**Use when:** something must change only behind the corporate proxy or CA.

**Steps**

1. Decide where it is read:

   | Read by | Put it in |
   |---|---|
   | Any shell or tool at runtime | The `{{ if .is_corporate }}` block of `dot_zshenv.tmpl` |
   | An install script, while it runs | That script's own corporate block (scripts run under `bash` and never read `.zshenv`) |
   | A tool's own config file | That file, made a template, inside `{{ if .is_corporate }}` |

2. For a tool that ignores the system CA store, point its CA variable at
   `/usr/local/share/ca-certificates/corporate-root-ca.crt` on Linux and at
   `{{ .corporate_ca_cert_source_path }}` on macOS (see `NODE_EXTRA_CA_CERTS` in `dot_zshenv.tmpl`).
3. Add a `bootstrap-corporate` check that the tool works through the proxy, and a negative control
   that it fails without the setting.

**Verify:** `bootstrap-corporate`, including the negative control.

**Pitfall:** a positive check alone. It passed for `PIP_CERT`, which turned out to be redundant:
Ubuntu's pip already trusts the system store. The negative control is what proves the setting
matters.

### R5. Add an OS-dependent path

**Use when:** a path differs between macOS and Linux and is used in more than one file.

**Steps**

1. Create `.chezmoitemplates/<name>`:

   ```
   {{- if eq .chezmoi.os "darwin" -}}/path/on/macos{{- else -}}/path/on/linux{{- end -}}
   ```

2. Use it as `{{ template "<name>" . }}` wherever the path appears.

**Verify:** the template checks render it per OS; the manual `macos` job covers the macOS side.

**Pitfall:** dropping the `-` trim markers. The partial then renders a trailing newline into the
middle of a line.

### R6. Change an existing run_once_ script

**Use when:** editing any `run_once_after_*` script.

**Steps**

1. Expect a re-run on every machine whose **rendered** content changes. A change inside a
   `{{ if eq .chezmoi.os "darwin" }}` branch re-runs on macOS only.
2. Keep it idempotent: installers that skip when already installed, `[[ -x … ]]` guards, and no
   appends to managed files.
3. When replacing an install method, remove the old artifact explicitly if an old one can shadow
   the new one on PATH. To upgrade a Linux release tool, change its pin in
   `.chezmoidata/linux-tools.toml`; `install_release` replaces the old version itself.

**Verify:** both bootstrap jobs; a second `chezmoi apply` in CI must change nothing.

**Pitfall:** an old binary in `~/.local/bin` shadows the new one, because `~/.local/bin` precedes
Homebrew (macOS) and the system directories on PATH.

### R7. Re-run a run_once_ script on one machine

**Use when:** a script was skipped or must run again without changing it.

**Steps**

1. Run only that script:

   ```bash
   chezmoi execute-template < "$(chezmoi source-path)/run_once_after_19-install-neovim-lazyvim.sh.tmpl" | bash
   ```

**Verify:** the script's own self-check output.

**Pitfall:** `chezmoi state delete-bucket --bucket=scriptState` re-runs **every** `run_once_`
script on the next apply.

### R8. Add a managed file under ~/.config/nvim

**Use when:** a Neovim config file should be the same on every machine.

**Steps**

1. Add it under `dot_config/nvim/`, e.g. `dot_config/nvim/lua/plugins/<name>.lua`.
2. Add its target path to `managed_re` in `run_once_after_19-install-neovim-lazyvim.sh.tmpl`, e.g.
   `^(lazyvim\.json|lua/plugins/sql\.lua|lua/plugins/<name>\.lua)$`.

**Verify:** the `templates` check `nvim: managed_re covers every file under dot_config/nvim`.

**Pitfall:** skipping step 2. Fresh machines then see an unmanaged file and skip the LazyVim
bootstrap; the CI guard exists to catch exactly this.

### R9. Change the LazyVim Extras seed

**Use when:** new machines should get a different set of Extras.

**Steps**

1. Edit the `extras` list in `dot_config/nvim/create_lazyvim.json`, using full module names such as
   `lazyvim.plugins.extras.lang.go`.
2. Update the count in the `templates.sh` check `nvim: lazyvim.json seeds 12 extras`.

**Verify:** the template check; `bootstrap-*` sync the plugins.

**Pitfall:** expecting existing machines to change. The file is `create_`: it is never overwritten.
On existing machines, use `:LazyExtras`.

### R10. Add a CI check

**Use when:** a change needs proof that survives later changes.

**Steps**

1. Choose the file:

   | Proves | File | Section |
   |---|---|---|
   | Rendered text (a line present or absent, per OS or profile) | `.github/ci/templates.sh` | Uses `$C` (corporate render) and `$P` (personal render) |
   | Behavior after a real bootstrap | `.github/ci/in-container.sh` | Common section, or the `if [[ $mode == corporate ]]` block |

2. Use the helper: `check "<area>: <what is true>" <command>`. Helpers in `templates.sh`: `has`,
   `lacks`, `count_is`, `first_line`.
3. For network or trust behavior, pair the positive check with a negative control.

**Verify:** run the check locally and see it fail once (for example by breaking the line it checks).

**Pitfall:** a check that cannot fail. Prove it fails when the thing it guards is broken.

### R11. Add or change a diagram

**Use when:** documenting a flow in [ARCHITECTURE.md](ARCHITECTURE.md).

**Steps**

1. One concept per diagram, at most **8 nodes**; split larger flows.
2. Quote every label (`A["label"]`), and avoid `;` and `#` inside labels.
3. Follow it with one sentence saying what to notice.

**Verify:** `.github/ci/docs.sh` renders every diagram.

**Pitfall:** a diagram that restates a table. Use a diagram only for flow or dependency.

## Pull requests

- Branch from the branch your change depends on, and set the PR base to it; retarget to `main` once
  the base merges.
- In the description, list what changed and the evidence (CI run, logs) for each claim.
- Keep a **Verification** checklist; tick an item only with a link to the run that proves it.
