#!/bin/sh
# The release app's smoke launch, RELEASE=<path to .app> or build/nmux.app: on a private tmux server it attaches one
# Session's plain client, and SIGTERM ends it with 0. It has no self-test, so the seam reads only tmux and the exit.
set -u
cd "$(dirname "$0")/../.."
. Tests/seam/lib.sh
BIN=${RELEASE:-build/nmux.app}/Contents/MacOS/nmux
# The release app uses tmux's default socket name, which this short TMUX_TMPDIR makes private.
export TMUX_TMPDIR="$HOME/.cache/nt-smoke-$$"
T="env -u TMUX TMUX_TMPDIR=$TMUX_TMPDIR tmux"
mkdir -p "$TMUX_TMPDIR" build/seam
# The smoke starts the server with no config, so the contributor's own ~/.tmux.conf never steers it.
$T -f /dev/null start-server \; set -s exit-empty off

oneClient() {
    [ "$($T list-sessions -F "#{session_id}" 2>/dev/null | wc -l)" -eq 1 ] \
        && [ "$(plains "#{session_id}")" = "$($T list-sessions -F "#{session_id}")" ]
}

launch smoke
check "the release app gives its one Session one plain client within 10 s" within 10 oneClient
kill "$PID"
check "the release app quits on SIGTERM" ended
check "and exits with 0" [ "$status" -eq 0 ]

[ $FAILS -eq 0 ]
