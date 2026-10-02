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
# #9 moved gh to Homebrew on Linux too, so the helper path follows the Homebrew prefix.
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

# #6 / #9: brew shellenv with the per-OS prefix, before the PATH export, in .zshrc and every brew script.
shellenv="eval \"\$($brew_prefix/bin/brew shellenv)\""
check "#6/#9 .zshrc evals brew shellenv ($brew_prefix)" has "$C/dot_zshrc" "$shellenv"
check "#6/#9 brew shellenv precedes the PATH export" \
    bash -c "[[ \$(grep -nF 'brew shellenv' '$C/dot_zshrc' | cut -d: -f1) -lt \$(grep -n '^export PATH=' '$C/dot_zshrc' | cut -d: -f1) ]]"
for script in run_once_after_15-build-lazygit.sh run_once_after_17-install-gh.sh run_once_after_18-install-ripgrep-fd.sh; do
    check "#9 $script evals brew shellenv ($brew_prefix)" has "$C/$script" "$shellenv"
done
check "#9 after_05 targets $brew_prefix/bin/brew" has "$C/run_once_after_05-install-homebrew.sh" "brew_bin=\"$brew_prefix/bin/brew\""
check "#9 after_15 installs lazygit via brew, no Go build" \
    bash -c "grep -qF 'brew install lazygit' '$C/run_once_after_15-build-lazygit.sh' && ! grep -q 'go build' '$C/run_once_after_15-build-lazygit.sh'"
check "#9 after_17 installs gh via brew" has "$C/run_once_after_17-install-gh.sh" "brew install gh"
check "#9 after_18 installs ripgrep and fd via brew" has "$C/run_once_after_18-install-ripgrep-fd.sh" "brew install ripgrep fd"
check "#9 after_10 no longer installs ripgrep, fd-find, or gh" \
    bash -c "! grep -qE '^ +(ripgrep|fd-find|gh)( |\\\\|\$)' '$C/run_once_after_10-install-apt-packages.sh'"
if [[ $os == Linux ]]; then
    check "#9 Linux after_05 installs Homebrew prerequisites, non-interactive" \
        bash -c "grep -qF 'apt-get install -y build-essential procps curl file git' '$C/run_once_after_05-install-homebrew.sh' && grep -qF 'NONINTERACTIVE=1' '$C/run_once_after_05-install-homebrew.sh'"
fi

# #3 live check (macOS runner): the rendered helper returns credentials with a GUI-style PATH.
if [[ $os == Darwin && -n "${GH_TOKEN:-}" ]]; then
    check "#3 helper returns credentials with PATH=/usr/bin:/bin:/usr/sbin:/sbin" bash -c "
        printf 'protocol=https\nhost=github.com\n\n' \
        | env PATH=/usr/bin:/bin:/usr/sbin:/sbin GIT_CONFIG_GLOBAL='$C/dot_gitconfig' GIT_TERMINAL_PROMPT=0 \
              /usr/bin/git credential fill 2>/dev/null | grep -q '^password='"
fi

exit "$fail"
