#!/bin/bash
set -euo pipefail
app="${1:?Missing app path}"
diagnostics="${2:?Missing diagnostics directory}"
mkdir -p "$diagnostics"
"$app/Contents/MacOS/AltServer" > "$diagnostics/runtime.log" 2>&1 &
app_pid=$!
cleanup() {
    kill -TERM "$app_pid" 2>/dev/null || true
    wait "$app_pid" 2>/dev/null || true
}
trap cleanup EXIT
for ((i=0; i<30; i++)); do
    sleep 1
    if ! kill -0 "$app_pid" 2>/dev/null; then
        cat "$diagnostics/runtime.log"
        echo 'AltServer exited during the startup smoke test' >&2
        exit 1
    fi
done
lsof -nP -a -p "$app_pid" -iTCP -sTCP:LISTEN > "$diagnostics/runtime-listeners.txt"
echo 'AltServer survived 30 seconds and opened its TCP listener.'
