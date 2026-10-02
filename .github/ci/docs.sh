#!/usr/bin/env bash
# Renders every Mermaid diagram in the root Markdown docs (any syntax error fails), then checks
# links, anchors, and backticked repo paths. Needs Docker and python3.
set -euo pipefail

ci="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
image=ghcr.io/mermaid-js/mermaid-cli/mermaid-cli

python3 "$ci/check_links.py" --extract-mermaid "$work"

fail=0
for diagram in "$work"/*.mmd; do
    name="$(basename "$diagram" .mmd)"
    if docker run --rm -u "$(id -u):$(id -g)" -v "$work:/data" "$image" \
        -i "/data/$name.mmd" -o "/data/$name.svg" >"$work/$name.log" 2>&1; then
        echo "PASS  diagram ${name/-L/.md:}"
    else
        echo "FAIL  diagram ${name/-L/.md:}"
        sed 's/^/      /' "$work/$name.log"
        fail=1
    fi
done

python3 "$ci/check_links.py" || fail=1
exit "$fail"
