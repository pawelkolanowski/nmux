# The app seam's library: the private tmux server, the app's launch and end, and the checks more than one milestone
# uses. run.sh and smoke.sh source it from the repository's root.
#
# Prerequisites:
# - tmux 3.4 or newer on PATH.
# - A Retina screen, where the windows open: the self-test build opens on the screen of the highest scale. With only
#   1x screens, `scale 1 measures the cell again` fails.
# - About two and a half minutes for every run.
#
# The self-test. The self-test build logs `selftest: <event>` lines on stderr, which `launch` keeps
# in build/seam/<run>.log. Its tmux runs on the private server `-L nmux-test -f /dev/null`.
#
# Variables:
#   NMUX_SELFTEST_SCREEN=<file>    each time output settles for 0.4 s, the screen's text is written to the file.
#   NMUX_SELFTEST_CELLS="x,y ..."  the cells, apart by spaces, logged each time the frames settle for 0.4 s.
#   NMUX_SELFTEST_PRESS=<action>   pressed on every card that offers it, a moment after the card shows.
#   NMUX_SELFTEST_NO_KNOWN_PATHS   hides the known paths of tmux, so the login shell alone decides.
#
# On its own, the self-test:
#   - logs the bytes parsed each time output settles for 0.4 s; the first time, it probes the terminal.
#   - asks every 0.1 s whether a hold still stands.
#   - logs the named cells and the cursor each time the frames settle for 0.4 s.
#   - reads one frame back the first time the first named cell holds a glyph.
#
# Signals:
#   SIGUSR1   logs the longest gap between presented frames since the last SIGUSR1, then the frames presented so far.
#   SIGUSR2   takes the next resize step: the content three columns and two rows smaller, then half a cell wider than
#             its grid, then scale 1, then scale 2. Each step reads one frame back again and, 0.5 s later, logs the
#             content's size, grid and cell.

APP=${APP:-build/selftest/nmux.app}
BIN=$APP/Contents/MacOS/nmux
# The app's tmux sockets land in a short TMUX_TMPDIR of the seam's own, never the author's: a socket path over 104
# bytes fails, so the folder sits in ~/.cache.
export TMUX_TMPDIR="$HOME/.cache/nt-$$"
T="env -u TMUX tmux -L nmux-test -f /dev/null"
FAILS=0
PID=
LOG=

# Locals start with `_`: `local` scopes them dynamically, and a polled function may read a global of the same name.
# check <name> <command> [args...]: prints `ok   <name>` when the command passes, else `FAIL <name>`.
check() { local _name=$1; shift; if "$@"; then echo "ok   $_name"; else echo "FAIL $_name"; FAILS=$((FAILS + 1)); fi; }
# within <seconds> <command> [args...]: runs the command every 0.1 s until it passes, for at most that long.
within() { local _t=$(($1 * 10)); shift; soon "$_t" "$@"; }
# soon <tenths of a second> <command> [args...]
soon() {
    local _i=0 _n=$1; shift
    while [ $_i -lt "$_n" ]; do "$@" && return 0; sleep 0.1; _i=$((_i + 1)); done
    return 1
}
not() { ! "$@"; }
# is <text> <command> [args...]: the command prints exactly the text.
is() { local _want=$1; shift; [ "$("$@")" = "$_want" ]; }
# over <n> <command> [args...]: the command prints a number above n.
over() { local _n=$1; shift; [ "$("$@")" -gt "$_n" ]; }
logged() { grep -qxF "selftest: $1" "$LOG"; }
alive() { kill -0 "$PID" 2>/dev/null; }
# An app hung on its main thread never handles SIGTERM, and left running it steals the next run's keys.
stop() { kill "$PID" 2>/dev/null; within 3 not alive || kill -9 "$PID" 2>/dev/null; }
# ended: waits for the app gone, kills it when it is not, and keeps its exit code in $status.
ended() {
    local _gone; within 3 not alive; _gone=$?
    alive && kill -9 "$PID"; wait "$PID"; status=$?; PID=; return $_gone
}
# fresh: an empty private server of the seam's own, and no file an earlier run left.
# The seam starts the server, so its panes run the seam's shell, never a run's fake one, and it outlives its last
# Session. The tmux socket folder stays, so the last check still finds a default socket any run made.
fresh() {
    $T kill-server 2>/dev/null
    mkdir -p "$TMUX_TMPDIR" build/seam
    find "$TMUX_TMPDIR" -mindepth 1 -maxdepth 1 ! -name "tmux-$(id -u)" -exec rm -rf {} +
    $T start-server \; set -s exit-empty off
}
teardown() { [ -n "$PID" ] && alive && stop; PID=; $T kill-server 2>/dev/null; }
finish() { teardown; rm -rf "$TMUX_TMPDIR"; }
trap finish EXIT

# launch <run> [VAR=value...]: the app, its log in build/seam/<run>.log.
launch() { LOG=build/seam/$1.log; shift; rm -f "$LOG"; env -u TMUX "$@" "$BIN" >"$LOG" 2>&1 & PID=$!; }
# attached: the first Session, the lowest $ID.
attached() { sed -n "s/^selftest: attached \([^ ]*\)$/\1/p" "$LOG" | head -1; }
isAttached() { [ -n "$(attached)" ]; }
# holds: reads `W H C R w h s` and passes when content W x H points is C x R cells of w x h pixels at scale s,
# within the half point it is rounded up to.
holds() { awk '{ exit !(($3 * $5 / $7 - $1) ^ 2 <= 0.25 && ($4 * $6 / $7 - $2) ^ 2 <= 0.25) }'; }
# plains <format>: the plain clients.
plains() { $T list-clients -F "$1" 2>/dev/null; }
clients() { plains "#{session_id} #{client_control_mode}"; }
noClients() { [ -z "$($T list-clients)" ]; }
