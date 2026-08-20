#!/usr/bin/env sh

set -eu

launcher_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
qs_bin=${WAVE_LAUNCHER_QS:-qs}

start_launcher() {
    "$qs_bin" -p "$launcher_dir" --daemonize >/dev/null 2>&1
}

if [ -p /dev/stdin ] || [ -f /dev/stdin ]; then
    menu_tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/wave-launcher.XXXXXX")
    menu_input="$menu_tmpdir/input"
    menu_result="$menu_tmpdir/result"

    cleanup_menu() {
        rm -f -- "$menu_input" "$menu_result"
        rmdir -- "$menu_tmpdir" 2>/dev/null || true
    }

    trap cleanup_menu EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM

    tee "$menu_input" >/dev/null
    : >"$menu_result"

    if [ ! -s "$menu_input" ]; then
        exit 1
    fi

    menu_input_url="file://$menu_input"
    menu_result_url="file://$menu_result"

    if ! "$qs_bin" -p "$launcher_dir" ipc call launcher showMenu \
        "$menu_input_url" "$menu_result_url" >/dev/null 2>&1; then
        start_launcher

        attempt=0
        while [ "$attempt" -lt 50 ]; do
            if "$qs_bin" -p "$launcher_dir" ipc call launcher showMenu \
                "$menu_input_url" "$menu_result_url" >/dev/null 2>&1; then
                break
            fi
            attempt=$((attempt + 1))
            sleep 0.02
        done

        if [ "$attempt" -eq 50 ]; then
            printf '%s\n' "launcher: Quickshell started, but its IPC endpoint did not become ready" >&2
            exit 1
        fi
    fi

    while [ ! -s "$menu_result" ]; do
        sleep 0.02
    done

    IFS= read -r menu_status <"$menu_result" || menu_status=""
    if [ "$menu_status" = "selected" ]; then
        sed '1d' "$menu_result"
        exit 0
    fi
    exit 1
fi

if "$qs_bin" -p "$launcher_dir" ipc call launcher toggle >/dev/null 2>&1; then
    exit 0
fi

start_launcher

# Give Quickshell a brief moment to register its IPC endpoint.
attempt=0
while [ "$attempt" -lt 50 ]; do
    if "$qs_bin" -p "$launcher_dir" ipc call launcher open >/dev/null 2>&1; then
        exit 0
    fi
    attempt=$((attempt + 1))
    sleep 0.02
done

printf '%s\n' "launcher: Quickshell started, but its IPC endpoint did not become ready" >&2
exit 1
