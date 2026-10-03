#!/usr/bin/env bash
# Renders every template with corporate and personal data and checks the rendered output.
# Runs on Linux (CI container or local Docker) and on macOS; OS-specific checks follow `uname`.
# If GH_TOKEN is set on macOS, also checks the gh credential helper under a minimal PATH.
set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
os="$(uname -s)"
fail=0

check() {
    local name=$1; shift
    if "$@"; then echo "PASS  $name"; else echo "FAIL  $name"; fail=1; fi
}
has()        { grep -qF -- "$2" "$1"; }
lacks()      { ! grep -qF -- "$2" "$1"; }
count_is()   { [[ "$(grep -cF -- "$2" "$1")" == "$3" ]]; }
first_line() { [[ "$(head -n1 "$1")" == "$2" ]]; }

# chezmoi keys --promptBool/--promptString by the prompt text in .chezmoi.toml.tmpl, not the data key.
q_corp="Is this a corporate-managed machine (proxy/CA cert needed)"
q_proxy="Corporate proxy URL (e.g. http://proxy.corp.example:8080)"
q_ca="Path to exported corporate root CA cert (e.g. /mnt/c/Users/you/ca.crt)"

# Render .chezmoi.toml.tmpl into a config per profile, then every other template with it.
for profile in corp personal; do
    if [[ $profile == corp ]]; then
        prompts=(--promptBool "$q_corp=true"
                 --promptString "$q_proxy=http://proxy.test:8080"
                 --promptString "$q_ca=/mnt/c/corp-root-ca.crt")
    else
        prompts=(--promptBool "$q_corp=false")
    fi
    chezmoi execute-template --init "${prompts[@]}" < "$repo/.chezmoi.toml.tmpl" > "$work/$profile.toml"

    while IFS= read -r tmpl; do
        rel="${tmpl#"$repo"/}"
        out="$work/$profile/${rel%.tmpl}"
        mkdir -p "$(dirname "$out")"
        chezmoi --config "$work/$profile.toml" --source "$repo" execute-template < "$tmpl" > "$out"
    done < <(find "$repo" -name '*.tmpl' ! -name '.chezmoi.toml.tmpl' -not -path '*/.git/*')
    cp "$repo"/run_*.sh "$work/$profile/" 2>/dev/null || true
done

C="$work/corp"
P="$work/personal"

check "config: is_corporate renders true/false" \
    bash -c "grep -q 'is_corporate = true' '$work/corp.toml' && grep -q 'is_corporate = false' '$work/personal.toml'"

for script in "$C"/run_*.sh "$P"/run_*.sh; do
    check "bash -n $(basename "$(dirname "$script")")/$(basename "$script")" bash -n "$script"
done
# A bare `sudo -v` prompts for a NOPASSWD user in %sudo; scripts use `sudo -n true || sudo -v`.
check "sudo: no bare \`sudo -v\` line in rendered run_* scripts" \
    bash -c '! grep -lEx "[[:space:]]*sudo -v" "$@"' _ "$C"/run_*.sh "$P"/run_*.sh
if command -v zsh >/dev/null; then
    for f in "$C/dot_zshrc" "$C/dot_zshenv" "$P/dot_zshrc" "$P/dot_zshenv"; do
        check "zsh -n ${f#"$work"/}" zsh -n "$f"
    done
fi

# #2: proxy moved to .zshenv, cargo env owned by .zshenv, rustup told not to edit rc files.
check "#2 corp .zshenv has all four proxy exports" \
    bash -c "for v in HTTP_PROXY HTTPS_PROXY http_proxy https_proxy; do grep -q \"^export \$v=\" '$C/dot_zshenv' || exit 1; done"
check "#2 personal .zshenv has no proxy" lacks "$P/dot_zshenv" "_PROXY"
check "#2 .zshenv cargo line, both profiles" \
    bash -c "grep -qF '. \"\$HOME/.cargo/env\"' '$C/dot_zshenv' && grep -qF '. \"\$HOME/.cargo/env\"' '$P/dot_zshenv'"
check "#2 corp .zshrc no longer exports the proxy" lacks "$C/dot_zshrc" "HTTP_PROXY"
check "#2 after_11 passes --no-modify-path" has "$C/run_once_after_11-install-rustup.sh" "--no-modify-path"

# #3: gh credential helper, per-OS absolute path.
check "#3 .gitconfig starts with [credential" first_line "$C/dot_gitconfig" '[credential "https://github.com"]'
# #10 moved gh to Homebrew on Linux too, so the helper path follows the Homebrew prefix.
if [[ $os == Darwin ]]; then brew_prefix=/opt/homebrew; else brew_prefix=/home/linuxbrew/.linuxbrew; fi
gh_path=$brew_prefix/bin/gh
check "#3 .gitconfig helper is !$gh_path (x2)" count_is "$C/dot_gitconfig" "helper = !$gh_path auth git-credential" 2

# #4: Oh My Zsh keeps the managed .zshrc.
check "#4 after_14 sets KEEP_ZSHRC=yes" has "$C/run_once_after_14-install-oh-my-zsh.sh" "export KEEP_ZSHRC=yes"

# #5: Node and uv trust the corporate CA, corporate only.
check "#5 corp .zshenv sets UV_SYSTEM_CERTS=1" has "$C/dot_zshenv" "export UV_SYSTEM_CERTS=1"
check "#5 personal .zshenv has no CA variables" \
    bash -c "! grep -qE 'NODE_EXTRA_CA_CERTS|UV_SYSTEM_CERTS' '$P/dot_zshenv'"
check "#5 personal after_16 has no NODE_EXTRA_CA_CERTS" lacks "$P/run_once_after_16-install-mermaid-cli.sh" "NODE_EXTRA_CA_CERTS"
if [[ $os == Darwin ]]; then
    node_ca='export NODE_EXTRA_CA_CERTS="/mnt/c/corp-root-ca.crt"'
else
    node_ca='export NODE_EXTRA_CA_CERTS=/usr/local/share/ca-certificates/corporate-root-ca.crt'
fi
check "#5 corp .zshenv: $node_ca" has "$C/dot_zshenv" "$node_ca"
check "#5 corp after_16: $node_ca" has "$C/run_once_after_16-install-mermaid-cli.sh" "$node_ca"

# #6 / #10: guarded brew shellenv with the per-OS prefix: in .zshrc on macOS (before the PATH export),
# in .zshenv on Linux (so non-interactive shells get it), and in every brew script.
shellenv="eval \"\$($brew_prefix/bin/brew shellenv)\""
guarded="[[ -x $brew_prefix/bin/brew ]] && $shellenv"
if [[ $os == Darwin ]]; then rc_with=dot_zshrc rc_without=dot_zshenv; else rc_with=dot_zshenv rc_without=dot_zshrc; fi
for dir in "$C" "$P"; do
    check "#6/#10 $(basename "$dir") $rc_with has guarded brew shellenv ($brew_prefix)" has "$dir/$rc_with" "$guarded"
    check "#6/#10 $(basename "$dir") $rc_without has no brew shellenv" lacks "$dir/$rc_without" "brew shellenv"
done
if [[ $os == Darwin ]]; then
    check "#6/#10 brew shellenv precedes the PATH export" \
        bash -c "[[ \$(grep -nF 'brew shellenv' '$C/dot_zshrc' | cut -d: -f1) -lt \$(grep -n '^export PATH=' '$C/dot_zshrc' | cut -d: -f1) ]]"
else
    check "#10 Linux .zshrc starts at the PATH comment" first_line "$C/dot_zshrc" "# If you come from bash you might have to change your \$PATH."
fi

# ~/.local/bin on PATH in every zsh (.zshenv), deduplicated, and last so it precedes Homebrew/libpq.
user_bins='export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"'
for dir in "$C" "$P"; do
    p=$(basename "$dir")
    check "path: $p .zshenv dedups PATH (typeset -U path PATH)" bash -c "grep -qx 'typeset -U path PATH' '$dir/dot_zshenv'"
    check "path: $p .zshenv ends with the user-bin PATH export" bash -c '[[ "$(tail -n1 "$1")" == "$2" ]]' _ "$dir/dot_zshenv" "$user_bins"
done
for script in run_once_after_15-install-lazygit.sh run_once_after_17-install-gh.sh run_once_after_18-install-ripgrep-fd.sh; do
    check "#10 $script evals brew shellenv ($brew_prefix)" has "$C/$script" "$shellenv"
done
check "#10 after_05 targets $brew_prefix/bin/brew" has "$C/run_once_after_05-install-homebrew.sh" "brew_bin=\"$brew_prefix/bin/brew\""
check "#10 after_15 installs lazygit via brew, no Go build" \
    bash -c "grep -qF 'brew install lazygit' '$C/run_once_after_15-install-lazygit.sh' && ! grep -q 'go build' '$C/run_once_after_15-install-lazygit.sh'"
check "#10 after_17 installs gh via brew" has "$C/run_once_after_17-install-gh.sh" "brew install gh"
check "#10 after_18 installs ripgrep and fd via brew" has "$C/run_once_after_18-install-ripgrep-fd.sh" "brew install ripgrep fd"
check "#10 after_10 no longer installs ripgrep, fd-find, or gh" \
    bash -c "! grep -qE '^ +(ripgrep|fd-find|gh)( |\\\\|\$)' '$C/run_once_after_10-install-apt-packages.sh'"
check "#10 corp after_05 disables Homebrew analytics" \
    bash -c "grep -qx 'export HOMEBREW_NO_ANALYTICS=1' '$C/run_once_after_05-install-homebrew.sh' && grep -qx 'brew analytics off' '$C/run_once_after_05-install-homebrew.sh'"
check "#10 personal after_05 leaves analytics alone" lacks "$P/run_once_after_05-install-homebrew.sh" "analytics"
if [[ $os == Linux ]]; then
    check "#10 Linux after_05 installs Homebrew prerequisites, non-interactive" \
        bash -c "grep -qF 'apt-get install -y build-essential procps curl file git' '$C/run_once_after_05-install-homebrew.sh' && grep -qF 'NONINTERACTIVE=1' '$C/run_once_after_05-install-homebrew.sh'"
fi

# nvim: Neovim + LazyVim bootstrap (after_19), dev clients (after_20), shell env, managed nvim files.
A19="$C/run_once_after_19-install-neovim-lazyvim.sh"
A20="$C/run_once_after_20-install-dev-clients.sh"
check "nvim: after_19 evals brew shellenv" has "$A19" "$shellenv"
check "nvim: after_19 installs neovim, tree-sitter-cli, fzf" has "$A19" "brew install neovim tree-sitter-cli fzf"
if [[ $os == Darwin ]]; then
    check "nvim: after_19 installs the JetBrainsMono Nerd Font cask (macOS)" has "$A19" "brew install --cask font-jetbrains-mono-nerd-font"
    check "nvim: font cask failure is non-fatal (macOS)" has "$A19" "|| echo \"JetBrainsMono Nerd Font cask skipped"
else
    check "nvim: after_19 has no font cask on Linux" lacks "$A19" "font-jetbrains-mono-nerd-font"
fi
check "nvim: after_20 evals brew shellenv" has "$A20" "$shellenv"
check "nvim: after_20 installs dotnet, libpq, snowflake-cli" has "$A20" "brew install dotnet libpq snowflake-cli"
for dir in "$C" "$P"; do
    p=$(basename "$dir")
    check "nvim: $p .zshenv sets EDITOR/VISUAL guarded" has "$dir/dot_zshenv" \
        "[[ -x $brew_prefix/bin/nvim ]] && export EDITOR=$brew_prefix/bin/nvim VISUAL=$brew_prefix/bin/nvim"
    check "nvim: $p .zshenv sets DOTNET_ROOT guarded" has "$dir/dot_zshenv" \
        "[[ -d $brew_prefix/opt/dotnet/libexec ]] && export DOTNET_ROOT=$brew_prefix/opt/dotnet/libexec"
    check "nvim: $p .zshenv adds keg-only libpq to PATH" has "$dir/dot_zshenv" "export PATH=\"$brew_prefix/opt/libpq/bin:\$PATH\""
    check "nvim: $p .zshrc no longer has the commented EDITOR block" lacks "$dir/dot_zshrc" "EDITOR"
done
check "nvim: no PIP_CERT (Ubuntu's pip trusts the system store)" \
    bash -c "! grep -q PIP_CERT '$C/dot_zshenv' '$P/dot_zshenv'"
check "nvim: corp .zshenv and after_20 opt out of .NET telemetry" \
    bash -c "grep -qx 'export DOTNET_CLI_TELEMETRY_OPTOUT=1' '$C/dot_zshenv' && grep -qx 'export DOTNET_CLI_TELEMETRY_OPTOUT=1' '$A20'"
check "nvim: personal leaves .NET telemetry alone" \
    bash -c "! grep -q DOTNET_CLI_TELEMETRY_OPTOUT '$P/dot_zshenv' '$P/run_once_after_20-install-dev-clients.sh'"
check "nvim: after_10 installs python3-venv and checks ensurepip" \
    bash -c "grep -qE '^ +python3-venv ' '$C/run_once_after_10-install-apt-packages.sh' && grep -qF 'import ensurepip' '$C/run_once_after_10-install-apt-packages.sh'"
check "nvim: after_19 resumes an interrupted starter copy (marker)" has "$A19" '.lazyvim-bootstrap-incomplete'
# after_19 treats any file under ~/.config/nvim outside managed_re as a user config and skips. Every
# file chezmoi manages there must match it, or fresh machines would silently skip the bootstrap.
managed_re=$(sed -n "s/^managed_re='\(.*\)'\$/\1/p" "$A19")
uncovered=$(cd "$repo/dot_config/nvim" && find . -type f | sed 's#^\./##' | while IFS= read -r src; do
    printf '%s\n' "$src" | tr '/' '\n' \
        | sed -E 's/^((create|modify|private|readonly|executable|empty|exact|encrypted)_)+//; s/^dot_/./; s/\.tmpl$//' \
        | paste -sd/ -
done | grep -vE "$managed_re" || true)
check "nvim: managed_re covers every file under dot_config/nvim" test -n "$managed_re" -a -z "$uncovered"
if [[ -n "$uncovered" ]]; then echo "      uncovered: $uncovered"; fi
check "nvim: lazyvim.json seeds 12 extras" count_is "$repo/dot_config/nvim/create_lazyvim.json" '"lazyvim.plugins.extras.' 12
check "nvim: ~/.sqlfluff defaults to ansi" bash -c "grep -qx 'dialect = ansi' '$repo/dot_sqlfluff'"
# Lua comments start with "--", so drop comment lines before checking for CLI flags.
sql_code=$(grep -vE '^[[:space:]]*--' "$repo/dot_config/nvim/lua/plugins/sql.lua")
check "nvim: sql.lua passes --stdin-filename and no --dialect" \
    bash -c 'grep -qF -- "--stdin-filename" <<<"$1" && ! grep -qF -- "--dialect" <<<"$1"' _ "$sql_code"

# #3 live check (macOS runner): the rendered helper returns credentials with a GUI-style PATH.
if [[ $os == Darwin && -n "${GH_TOKEN:-}" ]]; then
    check "#3 helper returns credentials with PATH=/usr/bin:/bin:/usr/sbin:/sbin" bash -c "
        printf 'protocol=https\nhost=github.com\n\n' \
        | env PATH=/usr/bin:/bin:/usr/sbin:/sbin GIT_CONFIG_GLOBAL='$C/dot_gitconfig' GIT_TERMINAL_PROMPT=0 \
              /usr/bin/git credential fill 2>/dev/null | grep -q '^password='"
fi

exit "$fail"
