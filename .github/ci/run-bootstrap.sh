#!/usr/bin/env bash
# Bootstraps this repo in a fresh Ubuntu 24.04 container and runs in-container.sh's checks.
# Usage: run-bootstrap.sh personal|corporate
#   corporate: the test container sits on an --internal network whose only way out is a
#   TLS-intercepting mitmproxy, so any tool ignoring the proxy or the corporate CA fails.
set -euo pipefail

mode=${1:?usage: run-bootstrap.sh personal|corporate}
ci="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$ci/../.." && pwd)"
image=dotfiles-bootstrap-test

docker build --platform linux/amd64 -t "$image" "$ci"
common=(--rm --platform linux/amd64 -v "$repo:/src:ro" -v "$ci:/ci:ro")

if [[ $mode == personal ]]; then
    # Optional Homebrew download cache (CI sets HOMEBREW_CACHE_HOST). Never used for corporate:
    # that job exists to prove every download crosses the TLS-intercepting proxy.
    if [[ -n "${HOMEBREW_CACHE_HOST:-}" ]]; then
        mkdir -p "$HOMEBREW_CACHE_HOST"
        chmod a+rwx "$HOMEBREW_CACHE_HOST"
        # Mounted outside $HOME: Docker creates missing parents of a mount target as root, and a
        # root-owned ~/.cache would break puppeteer, uv, and pip.
        common+=(-v "$HOMEBREW_CACHE_HOST:/homebrew-cache" -e HOMEBREW_CACHE=/homebrew-cache)
    fi
    exec docker run "${common[@]}" "$image" /ci/in-container.sh personal
fi

net="dotfiles-corp-$$"
proxy="dotfiles-mitm-$$"
ca_dir="$(mktemp -d)"
cleanup() {
    docker rm -f "$proxy" >/dev/null 2>&1 || true
    docker network rm "$net" >/dev/null 2>&1 || true
    rm -rf "$ca_dir"
}
trap cleanup EXIT

docker network create --internal "$net" >/dev/null
# stream_large_bodies: pass toolchain downloads through instead of buffering them in memory.
docker run -d --name "$proxy" mitmproxy/mitmproxy \
    mitmdump --listen-port 8080 --set stream_large_bodies=1m >/dev/null
docker network connect --alias proxy "$net" "$proxy"

ca=/home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem
for _ in $(seq 30); do
    docker exec "$proxy" test -f "$ca" && break
    sleep 1
done
docker cp "$proxy:$ca" "$ca_dir/corp-root-ca.crt"

docker run "${common[@]}" --network "$net" \
    -v "$ca_dir/corp-root-ca.crt:/mnt/c/corp-root-ca.crt:ro" \
    -e PROXY_URL=http://proxy:8080 \
    "$image" /ci/in-container.sh corporate \
    || { echo "--- proxy log (last 80 lines)"; docker logs --tail 80 "$proxy"; exit 1; }
