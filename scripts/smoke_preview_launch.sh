#!/bin/zsh
set -euo pipefail

if [[ -z "${APP_PATH:-}" || ! -d "$APP_PATH" ]]; then
    print -u2 "APP_PATH must point to the preview application bundle"
    exit 1
fi

EXECUTABLE_PATH="$APP_PATH/Contents/MacOS/Docky"
if [[ ! -x "$EXECUTABLE_PATH" ]]; then
    print -u2 "Docky executable is missing: $EXECUTABLE_PATH"
    exit 1
fi

LOG_PATH="$(mktemp "${TMPDIR:-/tmp}/docky-preview-launch.XXXXXX")"
PID=""
cleanup() {
    if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
        kill -TERM "$PID" 2>/dev/null || true
        wait "$PID" 2>/dev/null || true
    fi
    rm -f "$LOG_PATH"
}
trap cleanup EXIT

DOCKY_TEST_MODE=1 "$EXECUTABLE_PATH" >"$LOG_PATH" 2>&1 &
PID=$!
sleep "${PREVIEW_LAUNCH_SMOKE_SECONDS:-5}"

if ! kill -0 "$PID" 2>/dev/null; then
    wait "$PID" 2>/dev/null || status=$?
    status="${status:-1}"
    print -u2 "Preview app exited during launch smoke test with status $status"
    cat "$LOG_PATH" >&2
    exit 1
fi

kill -TERM "$PID"
wait "$PID" 2>/dev/null || true
PID=""
print "Unsigned preview launch smoke test passed."
