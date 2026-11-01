#!/usr/bin/env bash
set -euo pipefail

queue_repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
queue_test_root="$(mktemp -d "${TMPDIR:-/tmp}/icpswap-withdraw-queue.XXXXXX")"
queue_moc="${MOC:-moc}"
queue_vessel="${VESSEL:-vessel}"
queue_dfx="${DFX:-dfx}"

queue_cleanup() {
    local status=$?
    (cd "$queue_test_root" && "$queue_dfx" stop >/dev/null 2>&1) || true
    if [[ "$status" -eq 0 ]]; then
        rm -rf "$queue_test_root"
    else
        printf 'Test artifacts: %s\n' "$queue_test_root" >&2
    fi
    exit "$status"
}
trap queue_cleanup EXIT

cd "$queue_repo_root"
read -r -a queue_packages <<< "$("$queue_vessel" sources)"
"$queue_moc" -c --hide-warnings "${queue_packages[@]}" -o "$queue_test_root/SwapPool.wasm" src/SwapPool.mo
"$queue_moc" --idl --hide-warnings "${queue_packages[@]}" -o "$queue_test_root/SwapPool.did" src/SwapPool.mo
"$queue_moc" -c --hide-warnings "${queue_packages[@]}" -o "$queue_test_root/MockLedger.wasm" test/withdraw-queue/MockLedger.mo
"$queue_moc" --idl --hide-warnings "${queue_packages[@]}" -o "$queue_test_root/MockLedger.did" test/withdraw-queue/MockLedger.mo
cp test/withdraw-queue/dfx.json "$queue_test_root/dfx.json"

cd "$queue_test_root"
"$queue_dfx" start --background --host 127.0.0.1:0 --artificial-delay 200
DFX="$queue_dfx" python3 "$queue_repo_root/test/withdraw-queue/run.py"
