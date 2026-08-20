#!/usr/bin/env sh

set -eu

launcher_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

if qs -p "$launcher_dir" ipc call launcher toggle >/dev/null 2>&1; then
    exit 0
fi

qs -p "$launcher_dir" --daemonize >/dev/null 2>&1

# Give Quickshell a brief moment to register its IPC endpoint.
attempt=0
while [ "$attempt" -lt 50 ]; do
    if qs -p "$launcher_dir" ipc call launcher open >/dev/null 2>&1; then
        exit 0
    fi
    attempt=$((attempt + 1))
    sleep 0.02
done

printf '%s\n' "launcher: Quickshell started, but its IPC endpoint did not become ready" >&2
exit 1
