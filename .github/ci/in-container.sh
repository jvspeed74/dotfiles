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

# Image preconditions. The control proves the NOPASSWD-in-%sudo case the run_* scripts must handle
# is present; without it a bare `sudo -v` in a script would pass CI.
check "sudo: control: bare sudo -n -v fails (group sudo + NOPASSWD)" bash -c '! sudo -n -v 2>/dev/null'
. /etc/os-release
if (( ${VERSION_ID%%.*} >= 26 )); then
    check "sudo: /usr/bin/sudo is sudo-rs on $VERSION_ID" test "$(readlink -f /usr/bin/sudo)" = /usr/lib/cargo/bin/sudo
fi

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
# env -i: this script's own PATH export (top) would otherwise hide a .zshenv without ~/.local/bin.
clean_zsh() { env -i HOME="$HOME" USER="$USER" zsh -c "$1"; }
check "path: chezmoi, uv, uvx resolve in non-interactive zsh from a clean env" \
    clean_zsh 'command -v chezmoi uv uvx >/dev/null'
check "path: non-interactive zsh PATH starts with ~/.local/bin" \
    test "$(clean_zsh 'print -r -- $path[1]' 2>/dev/null)" = "$HOME/.local/bin"
# Interactive: .zshrc may prepend more (e.g. Homebrew on macOS), so check order, not position.
clean_zsh_i() { env -i HOME="$HOME" USER="$USER" ${2:+PATH="$2"} zsh -i -c "$1" </dev/null 2>/dev/null; }
check "path: interactive zsh PATH starts with ~/.local/bin (Linux has no Homebrew)" \
    test "$(clean_zsh_i 'print -r -- $path[1]' | tail -n1)" = "$HOME/.local/bin"
check "path: interactive zsh PATH has no duplicate entries" \
    test -z "$(clean_zsh_i 'print -l $path' | sort | uniq -d)"
# A nested zsh keeps its parent's order: an activated venv first in the parent stays first. The
# parent is a fresh interactive shell (a terminal tab) with a venv's bin prepended.
venv=/tmp/venv-probe/bin
parent="$venv:$(clean_zsh_i 'print -rn -- $PATH')"
check "path: nested non-interactive zsh keeps the parent's first entry (venv)" \
    test "$(env -i HOME="$HOME" USER="$USER" PATH="$parent" zsh -c 'print -r -- $path[1]')" = "$venv"
check "path: nested interactive zsh keeps the parent's first entry (venv)" \
    test "$(clean_zsh_i 'print -r -- $path[1]' "$parent" | tail -n1)" = "$venv"
for tool in gh rg fd lazygit uv node mmdc; do
    check "tool resolves in interactive zsh: $tool" zsh -i -c "command -v $tool >/dev/null" </dev/null
done

# Node: .zshenv puts the newest nvm Node on PATH for every zsh; .zshrc loads nvm only on first use.
check "node: node, npm, npx, mmdc resolve in non-interactive zsh from a clean env" \
    clean_zsh 'command -v node npm npx mmdc >/dev/null'
node_ni=$(clean_zsh 'command -v node' 2>/dev/null)
check "node: non-interactive node is nvm's ($node_ni)" \
    bash -c '[[ $1 == "$HOME"/.nvm/versions/node/v*/bin/node ]]' _ "$node_ni"
check "node: interactive and non-interactive zsh resolve the same node" \
    test "$(clean_zsh_i 'command -v node' | tail -n1)" = "$node_ni"
check "node: interactive zsh does not load nvm at startup" \
    clean_zsh_i '! typeset -f nvm_ls_current >/dev/null'
check "node: nvm loads on first use and reports the PATH node" \
    test "$(clean_zsh_i 'nvm current' | tail -n1)" = "$(clean_zsh 'node --version')"
# Real nvm: install an older major beside the LTS. New shells keep the newest; a child zsh started
# after `nvm use <older>` keeps the older one (.zshenv must not re-prepend the newest).
node_new=$(clean_zsh 'node --version')
node_major=${node_new#v}; node_old=$(( ${node_major%%.*} - 2 ))
check "node: nvm installs an older Node ($node_old) beside $node_new" clean_zsh_i "nvm install $node_old >/dev/null 2>&1"
check "node: a fresh zsh still uses the newest Node ($node_new)" test "$(clean_zsh 'node --version')" = "$node_new"
node_child=$(clean_zsh_i "nvm use $node_old >/dev/null && zsh -c 'node --version'" | tail -n1)
check "node: child zsh -c keeps the parent's \`nvm use $node_old\` ($node_child)" \
    bash -c '[[ $1 == "v$2."* ]]' _ "$node_child" "$node_old"
# Linux tools: pinned GitHub releases linked from ~/.local/bin into ~/.local/opt; no Homebrew.
local_bin="$HOME/.local/bin"
for tool in gh rg fd lazygit nvim tree-sitter fzf; do
    check "release: $tool resolves to $local_bin in interactive and non-interactive zsh" \
        bash -c '[[ $(zsh -i -c "command -v $1" </dev/null 2>/dev/null | tail -n1) == "$2/$1" && $(zsh -c "command -v $1") == "$2/$1" ]]' _ "$tool" "$local_bin"
    check "release: $tool links into ~/.local/opt" bash -c '[[ $(readlink "$1") == "$HOME"/.local/opt/* ]]' _ "$local_bin/$tool"
    check "release: $tool runs" "$local_bin/$tool" --version
done
check "release: no Homebrew on Linux" test ! -e /home/linuxbrew
check "#8 chrome-headless-shell downloaded by after_16" \
    bash -c 'find "$HOME/.cache/puppeteer" -type f -name chrome-headless-shell -perm -u+x 2>/dev/null | grep -q .'
check "#4 no ~/.zshrc.pre-oh-my-zsh" test ! -e "$HOME/.zshrc.pre-oh-my-zsh"
# nvm and Oh My Zsh are git clones (their installers live on raw.githubusercontent.com).
check "#4 ~/.nvm is a git checkout of nvm v0.40.1" test "$(git -C "$HOME/.nvm" describe --tags 2>/dev/null)" = v0.40.1
check "#4 ~/.oh-my-zsh is a git clone of ohmyzsh" \
    test "$(git -C "$HOME/.oh-my-zsh" remote get-url origin 2>/dev/null)" = https://github.com/ohmyzsh/ohmyzsh.git
check "#4 omz update works on the clone" zsh -i -c 'omz update >/dev/null 2>&1' </dev/null
check "#4 ~/.zshrc matches the managed template" cmp -s <(chezmoi cat "$HOME/.zshrc") "$HOME/.zshrc"
check "chezmoi status is clean after bootstrap" test -z "$(chezmoi status)"
check "docs: README, GUIDE, ARCHITECTURE, CONTRIBUTING are not applied to ~" \
    test ! -e "$HOME/README.md" -a ! -e "$HOME/GUIDE.md" -a ! -e "$HOME/ARCHITECTURE.md" -a ! -e "$HOME/CONTRIBUTING.md"
check "repo: .gitattributes is not applied to ~" test ! -e "$HOME/.gitattributes"
if [[ -n "$(chezmoi status)" ]]; then chezmoi status; chezmoi diff | head -60; fi

check "#3 github.com helper is !$local_bin/gh" \
    bash -c "git config --get-all credential.https://github.com.helper | grep -qxF '!$local_bin/gh auth git-credential'"
cred_out=$(printf 'protocol=https\nhost=github.com\n\n' | GIT_TERMINAL_PROMPT=0 git credential fill 2>&1 || true)
check "#3 helper runs before gh auth login (no 'No such file')" \
    bash -c '! grep -qE "No such file|command not found" <<<"$1"' _ "$cred_out"

# nvim: Neovim + LazyVim bootstrap, dev clients, shell env.
# dotnet and psql from apt, snow from uv (PyPI).
for tool in dotnet psql; do
    check "nvim: $tool resolves to /usr/bin in non-interactive zsh" test "$(zsh -c "command -v $tool" 2>/dev/null)" = "/usr/bin/$tool"
done
check "nvim: snow resolves to $local_bin in non-interactive zsh" test "$(zsh -c 'command -v snow' 2>/dev/null)" = "$local_bin/snow"
check "nvim: dotnet SDK 10 installed" bash -c 'zsh -c "dotnet --list-sdks" | grep -q "^10\."'
check "nvim: Neovim >= 0.11.2" zsh -c "nvim --headless -c 'if has(\"nvim-0.11.2\") | qa | else | cq | endif'"
check "nvim: EDITOR and VISUAL are the release nvim" \
    test "$(zsh -c 'echo "$EDITOR|$VISUAL"')" = "$local_bin/nvim|$local_bin/nvim"
check "nvim: DOTNET_ROOT is apt's dotnet" test "$(zsh -c 'echo "$DOTNET_ROOT"')" = /usr/lib/dotnet
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
    # The corporate proxy blocks raw.githubusercontent.com and ghcr.io (as the real one does). Proves
    # the block is active; every install above succeeding proves nothing depends on those hosts.
    for blocked in https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh https://ghcr.io/v2/; do
        check "restricted: proxy blocks $blocked (403)" \
            test "$(zsh -c "curl -s -o /dev/null -w '%{http_code}' '$blocked'")" = 403
    done
    check "restricted: control: github.com release downloads pass the proxy" \
        test "$(zsh -c "curl -sL -o /dev/null -w '%{http_code}' https://github.com/cli/cli/releases/download/v2.102.0/gh_2.102.0_checksums.txt")" = 200
    check "CA installed by before_00" test -f /usr/local/share/ca-certificates/corporate-root-ca.crt

    check "#5 npm reaches the registry through the TLS proxy" zsh -i -c 'npm ping >/dev/null 2>&1' </dev/null
    # No retries: the failure is certain, and npm's default backoff spent about 70 s per run.
    npm_ctl=$(zsh -i -c 'unset NODE_EXTRA_CA_CERTS; npm ping --fetch-retries=0 2>&1' </dev/null || true)
    check "#5 control: npm fails with a cert error without NODE_EXTRA_CA_CERTS" grep -qi 'cert' <<<"$npm_ctl"

    check "#5 uv downloads through the TLS proxy" zsh -i -c \
        'uv venv -q /tmp/uv-ok && uv pip install -q --python /tmp/uv-ok --no-cache six' </dev/null
    uv_ctl=$(zsh -i -c 'unset UV_SYSTEM_CERTS; uv pip install --python /tmp/uv-ok --no-cache --reinstall six 2>&1' </dev/null || true)
    check "#5 control: uv fails with a cert error without UV_SYSTEM_CERTS" grep -qi 'certif' <<<"$uv_ctl"

    check "nvim: pip installs through the TLS proxy (system CA store)" zsh -c \
        'python3 -m venv /tmp/pip-ok && /tmp/pip-ok/bin/pip install -q --no-cache-dir six'
fi

exit "$fail"
