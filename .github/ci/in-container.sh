#!/usr/bin/env bash
# Runs inside the test container as `tester`: follows the README bootstrap, then checks the result.
# Usage: in-container.sh personal|corporate   (corporate expects PROXY_URL and /mnt/c/corp-root-ca.crt)
set -euo pipefail

mode=${1:?usage: in-container.sh personal|corporate}
export PATH="$HOME/.local/bin:$PATH"
fail=0

check() {
    local name=$1; shift
    if "$@"; then echo "PASS  $name"; else echo "FAIL  $name"; fail=1; fi
}

# The source is the checked-out tree, standing in for the one-liner's GitHub clone.
mkdir -p "$HOME/.local/share"
cp -r /src "$HOME/.local/share/chezmoi"

# chezmoi keys --promptBool/--promptString by the prompt text in .chezmoi.toml.tmpl, not the data key.
q_corp="Is this a corporate-managed machine (proxy/CA cert needed)"
q_proxy="Corporate proxy URL (e.g. http://proxy.corp.example:8080)"
q_ca="Path to exported corporate root CA cert (e.g. /mnt/c/Users/you/ca.crt)"

if [[ $mode == corporate ]]; then
    # README "Corporate WSL" step 4: trust the corporate CA before anything downloads.
    sudo cp /mnt/c/corp-root-ca.crt /usr/local/share/ca-certificates/corporate-root-ca.crt && sudo update-ca-certificates
    # Step 5: export the proxy in the current shell.
    export http_proxy=$PROXY_URL https_proxy=$PROXY_URL HTTP_PROXY=$PROXY_URL HTTPS_PROXY=$PROXY_URL
    prompts=(--promptBool "$q_corp=true"
             --promptString "$q_proxy=$PROXY_URL"
             --promptString "$q_ca=/mnt/c/corp-root-ca.crt")
else
    prompts=(--promptBool "$q_corp=false")
fi

# Step 6: the one-liner. `set -e` fails the run if any script fails.
echo "=== bootstrap ($mode)"
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin" init --apply "${prompts[@]}"

echo "=== checks ($mode)"
check "#2 login shell is /usr/bin/zsh" test "$(getent passwd "$USER" | cut -d: -f7)" = /usr/bin/zsh
check "#2 cargo resolves in non-interactive zsh (.zshenv)" zsh -c 'command -v cargo >/dev/null'
check "#2 .zshenv has exactly one cargo env line" test "$(grep -c '.cargo/env' "$HOME/.zshenv")" = 1
for tool in brew gh rg fd lazygit uv node mmdc; do
    check "tool resolves in interactive zsh: $tool" zsh -i -c "command -v $tool >/dev/null" </dev/null
done
brew_bin=/home/linuxbrew/.linuxbrew/bin
for tool in gh rg fd lazygit; do
    check "#10 $tool resolves to Homebrew ($brew_bin)" \
        test "$(zsh -i -c "command -v $tool" </dev/null 2>/dev/null)" = "$brew_bin/$tool"
done
check "#10 brew tools resolve in non-interactive zsh (.zshenv)" zsh -c 'command -v gh rg fd lazygit >/dev/null'
check "#10 no stale ~/.local/bin/fd or ~/.local/bin/lazygit" \
    test ! -e "$HOME/.local/bin/fd" -a ! -e "$HOME/.local/bin/lazygit"
check "#8 chrome-headless-shell downloaded by after_16" \
    bash -c 'find "$HOME/.cache/puppeteer" -type f -name chrome-headless-shell -perm -u+x 2>/dev/null | grep -q .'
check "#4 no ~/.zshrc.pre-oh-my-zsh" test ! -e "$HOME/.zshrc.pre-oh-my-zsh"
check "#4 ~/.zshrc matches the managed template" cmp -s <(chezmoi cat "$HOME/.zshrc") "$HOME/.zshrc"
check "chezmoi status is clean after bootstrap" test -z "$(chezmoi status)"
check "docs: README, GUIDE, ARCHITECTURE, CONTRIBUTING are not applied to ~" \
    test ! -e "$HOME/README.md" -a ! -e "$HOME/GUIDE.md" -a ! -e "$HOME/ARCHITECTURE.md" -a ! -e "$HOME/CONTRIBUTING.md"
if [[ -n "$(chezmoi status)" ]]; then chezmoi status; chezmoi diff | head -60; fi

check "#3/#10 github.com helper is !$brew_bin/gh" \
    bash -c "git config --get-all credential.https://github.com.helper | grep -qxF '!$brew_bin/gh auth git-credential'"
cred_out=$(printf 'protocol=https\nhost=github.com\n\n' | GIT_TERMINAL_PROMPT=0 git credential fill 2>&1 || true)
check "#3 helper runs before gh auth login (no 'No such file')" \
    bash -c '! grep -qE "No such file|command not found" <<<"$1"' _ "$cred_out"

# nvim: Neovim + LazyVim bootstrap, dev clients, shell env.
prefix=/home/linuxbrew/.linuxbrew
for tool in nvim tree-sitter fzf dotnet snow; do
    check "nvim: $tool resolves to Homebrew in non-interactive zsh" \
        test "$(zsh -c "command -v $tool" 2>/dev/null)" = "$prefix/bin/$tool"
done
check "nvim: psql resolves to keg-only libpq in non-interactive zsh" \
    test "$(zsh -c 'command -v psql' 2>/dev/null)" = "$prefix/opt/libpq/bin/psql"
check "nvim: Neovim >= 0.11.2" zsh -c "nvim --headless -c 'if has(\"nvim-0.11.2\") | qa | else | cq | endif'"
check "nvim: EDITOR and VISUAL are Homebrew nvim" \
    test "$(zsh -c 'echo "$EDITOR|$VISUAL"')" = "$prefix/bin/nvim|$prefix/bin/nvim"
check "nvim: DOTNET_ROOT is Homebrew dotnet" test "$(zsh -c 'echo "$DOTNET_ROOT"')" = "$prefix/opt/dotnet/libexec"
check "nvim: LazyVim starter present without .git" \
    test -f "$HOME/.config/nvim/lua/config/lazy.lua" -a ! -e "$HOME/.config/nvim/.git"
for plugin in lazy.nvim LazyVim vim-dadbod crates.nvim chezmoi.nvim; do
    check "nvim: plugin installed: $plugin" test -d "$HOME/.local/share/nvim/lazy/$plugin"
done
check "nvim: lazyvim.json is valid JSON with the seeded extras" python3 -c '
import json, os, sys
e = json.load(open(os.path.expanduser("~/.config/nvim/lazyvim.json")))["extras"]
sys.exit(0 if len(e) >= 12 and all(x.startswith("lazyvim.plugins.extras.") for x in e) else 1)'
check "nvim: ~/.sqlfluff defaults to ansi" grep -qx 'dialect = ansi' "$HOME/.sqlfluff"

# Skip test: with an unmanaged file in ~/.config/nvim (plus the two chezmoi-managed files), after_19
# must warn, exit 0, and change nothing. The bootstrapped config is restored afterwards.
mv "$HOME/.config/nvim" /tmp/nvim-bootstrapped
mkdir -p "$HOME/.config/nvim/lua/plugins"
echo '" pre-existing config' > "$HOME/.config/nvim/init.vim"
cp /tmp/nvim-bootstrapped/lazyvim.json "$HOME/.config/nvim/"
cp /tmp/nvim-bootstrapped/lua/plugins/sql.lua "$HOME/.config/nvim/lua/plugins/"
fingerprint() { (cd "$HOME/.config/nvim" && find . -type f | sort | xargs sha256sum); }
before=$(fingerprint)
skip_rc=0
skip_out=$(chezmoi execute-template < "$HOME/.local/share/chezmoi/run_once_after_19-install-neovim-lazyvim.sh.tmpl" | bash 2>&1) || skip_rc=$?
check "nvim: skip test exits 0" test "$skip_rc" = 0
check "nvim: skip test warns" grep -q 'skipping the LazyVim bootstrap' <<<"$skip_out"
check "nvim: skip test leaves the existing config unchanged" test "$before" = "$(fingerprint)"
rm -rf "$HOME/.config/nvim"
mv /tmp/nvim-bootstrapped "$HOME/.config/nvim"

# Resume test: a copy interrupted after one starter file (marker still present) must finish on the
# next run instead of being mistaken for a user config.
mv "$HOME/.config/nvim" /tmp/nvim-bootstrapped
mkdir -p "$HOME/.config/nvim/lua/plugins"
touch "$HOME/.config/nvim/.lazyvim-bootstrap-incomplete"
cp /tmp/nvim-bootstrapped/init.lua "$HOME/.config/nvim/"
cp /tmp/nvim-bootstrapped/lazyvim.json "$HOME/.config/nvim/"
cp /tmp/nvim-bootstrapped/lua/plugins/sql.lua "$HOME/.config/nvim/lua/plugins/"
resume_rc=0
resume_out=$(chezmoi execute-template < "$HOME/.local/share/chezmoi/run_once_after_19-install-neovim-lazyvim.sh.tmpl" | bash 2>&1) || resume_rc=$?
check "nvim: resume test exits 0" test "$resume_rc" = 0
check "nvim: resume test reports resuming" grep -q 'Resuming an interrupted LazyVim bootstrap' <<<"$resume_out"
check "nvim: resume test completes the starter and clears the marker" \
    test -f "$HOME/.config/nvim/lua/config/lazy.lua" -a ! -e "$HOME/.config/nvim/.lazyvim-bootstrap-incomplete"
rm -rf "$HOME/.config/nvim"
mv /tmp/nvim-bootstrapped "$HOME/.config/nvim"

check "second chezmoi apply succeeds" chezmoi apply
check "chezmoi status is clean after second apply" test -z "$(chezmoi status)"

if [[ $mode == corporate ]]; then
    env_dump=$(zsh -c env)
    for var in http_proxy https_proxy HTTP_PROXY HTTPS_PROXY NODE_EXTRA_CA_CERTS UV_SYSTEM_CERTS DOTNET_CLI_TELEMETRY_OPTOUT; do
        check "#2/#5 $var set in non-interactive zsh" grep -q "^$var=" <<<"$env_dump"
    done
    check "apt proxy config written" test -f /etc/apt/apt.conf.d/95corporate-proxy
    check "#10 Homebrew analytics disabled" bash -c 'zsh -c "brew analytics state" 2>&1 | grep -qi disabled'
    check "CA installed by before_00" test -f /usr/local/share/ca-certificates/corporate-root-ca.crt

    check "#5 npm reaches the registry through the TLS proxy" zsh -i -c 'npm ping >/dev/null 2>&1' </dev/null
    npm_ctl=$(zsh -i -c 'unset NODE_EXTRA_CA_CERTS; npm ping 2>&1' </dev/null || true)
    check "#5 control: npm fails with a cert error without NODE_EXTRA_CA_CERTS" grep -qi 'cert' <<<"$npm_ctl"

    check "#5 uv downloads through the TLS proxy" zsh -i -c \
        'uv venv -q /tmp/uv-ok && uv pip install -q --python /tmp/uv-ok --no-cache six' </dev/null
    uv_ctl=$(zsh -i -c 'unset UV_SYSTEM_CERTS; uv pip install --python /tmp/uv-ok --no-cache --reinstall six 2>&1' </dev/null || true)
    check "#5 control: uv fails with a cert error without UV_SYSTEM_CERTS" grep -qi 'certif' <<<"$uv_ctl"

    check "nvim: pip installs through the TLS proxy (system CA store)" zsh -c \
        'python3 -m venv /tmp/pip-ok && /tmp/pip-ok/bin/pip install -q --no-cache-dir six'
fi

exit "$fail"
