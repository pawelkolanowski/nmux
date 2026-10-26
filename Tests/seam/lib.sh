# The app seam's library: the private tmux server, the app's launch and end, and the checks more than one milestone
# uses. run.sh and smoke.sh source it from the repository's root.
#
# Prerequisites:
# - tmux 3.4 or newer on PATH.
# - A Retina screen, where the windows open: the self-test build opens on the screen of the highest scale. With only
#   1x screens, `scale 1 measures the cell again` and the candidate window's rect fail.
# - About two and a half minutes for every run.
#
# The self-test's command language. The self-test build logs `selftest: <event>` lines on stderr, which `launch` keeps
# in build/seam/<run>.log. Its tmux runs on the private server `-L nmux-test -f /dev/null`, and Open Config logs
# `open-config <path>` in place of opening an editor.
#
# Variables:
#   NMUX_SELFTEST_SCREEN=<file>    each time output settles for 0.4 s, the screen's text is written to the file.
#   NMUX_SELFTEST_CELLS="x,y ..."  the cells, apart by spaces, logged each time the frames settle for 0.4 s.
#   NMUX_SELFTEST_KEYS=<file>      each line the file gains is one command, below.
#   NMUX_SELFTEST_PRESS=<action>   pressed on every card that offers it, a moment after the card shows.
#   NMUX_SELFTEST_FONT=<file>      a face file in the app's Resources/Fonts to draw in, in place of the config's.
#   NMUX_SELFTEST_NO_KNOWN_PATHS   hides the known paths of tmux, so the login shell alone decides.
#
# On its own, the self-test:
#   - logs the bytes parsed each time output settles for 0.4 s; the first time, it probes the terminal.
#   - asks every 0.1 s whether a hold still stands.
#   - logs the named cells, the rows the last rebuild shaped and the cursor each time the frames settle for 0.4 s.
#   - reads one frame back the first time the first named cell holds a glyph, again after each commit, and after each
#     switch of Session. It watches every Session's view and acts on the shown one.
#   - logs `selection <x0>,<y0>-<x1>,<y1>` or `selection none` for each settled frame whose selection differs from the
#     last logged one, and reads a frame back again.
#   - logs `key <keycode> <mods> -> <hex>` for each key the view sends, `none` when the encoder made no bytes.
#   - logs `preedit <hex>` for each marked text change, empty when it goes, and `commit <hex>` for each commit.
#   - logs `mouse <action> <button> <col>,<row> -> <hex>` for each mouse report, and `open <url>` for each link opened,
#     the open skipped.
#   - copies to a pasteboard of its own and logs `copy <hex>` for each copy.
#   - logs `paste <hex> bracketed=<yes|no>` for each paste sent, whether the pane turned bracketed paste on.
#   - logs `osc52 write <hex>` for each OSC 52 write that reached the pasteboard, and `osc52 read <hex>` for each OSC 52
#     read answered, `empty` for no text, or `osc52 read none` for no reply.
#
# Signals:
#   SIGUSR1   logs the longest gap between presented frames since the last SIGUSR1, then the frames presented so far.
#   SIGUSR2   takes the next resize step: the content three columns and two rows smaller, then half a cell wider than
#             its grid, then scale 1, then scale 2. Each step reads one frame back again and, 0.5 s later, logs the
#             content's size, grid and cell.
#
# NMUX_SELFTEST_KEYS lines:
#   <keycode> <flags> <chars> [mark:<hex>|insert:<hex>]
#       One key pressed and let go through NSApp.sendEvent: the keycode in decimal, the modifier flags in hex with
#       their device masks, the characters as UTF-8 hex or `-` for none. The fourth field is what the text system does
#       with the key in place of the input source, which a synthetic key never reaches.
#   mark <hex>          the text input client sets marked text.
#   insert <hex>        the text input client inserts text outside a key.
#   rect                logs `rect <x> <y> <w> <h>`, the first rect for an empty range in points from the view's top
#                       left.
#   click <left|right|middle> <col>,<row> <flags>
#                       presses and lets go at the cell's middle. Mouse events go to the view's own handler, since a
#                       window that is not key takes a click for itself, and carry the time they are made, so clicks
#                       in one poll repeat.
#   move <col>,<row> <flags>
#                       moves the pointer there.
#   wheel <points> <precise 0|1> <count> <flags>
#                       scrolls `count` times at the pointer, by whole points or notches.
#   pointer             logs `pointer <hand|ibeam|other>`, the view's pointer as it stands.
#   drag <col>,<row> <col>,<row> <flags>
#                       presses the left button near the first cell's left edge, drags to near the second's right edge
#                       and lets go there.
#   pasteboard          logs `pasteboard <hex>` or `pasteboard none`.
#   pasteboard <hex>    writes that string to the pasteboard.
#   create [<name>]     creates a Session through `create`.
#   goto <shortcut>     performs that Session shortcut through `perform`.
#   pill <n>            clicks the middle of the n-th pill from 1, through the window's hit test, and logs
#                       `pill <n> missed` when the click lands elsewhere.
#   width <points>      sets the content's width and reads one frame back again.
#   barback             draws the Session bar off screen and logs `barback bg ok` when its right end, past the row,
#                       shows the theme's background, else `barback bg <hex>`.
#   plus                clicks the plus the same way as `pill`.
#   plus rest           has the pointer come to rest on the plus.
#   type <text>         presses one key per character through NSApp.sendEvent, to whichever view has the focus.
#   return, escape      press those keys the same way.
#   cup                 clicks the Keep-awake cup the same way as the plus.
#   cup rest            has the pointer come to rest on the cup.
#   washback            draws the window's layers as they show now and logs `washback plain` when the bar's right
#                       end shows the theme's background, `washback tinted` when it lies nearer the accent than that,
#                       else `washback <hex>`.
#   washback pill <n>   reads the n-th pill 8 pt from its left edge the same way, against the danger colour.
#   washback card       reads the window inside the card's default button, against the accent; with no card, where
#                       the last card's button was.
#   close <n>           clicks the n-th pill's close mark, as `pill` clicks.
#   bin <$id>           clicks the bin on that Session's pill, as `pill` clicks. Every such click answers an asking pill
#                       first, as a click in the window does.
#   close button        presses the window's close button, as Closing nmux does.
#   box                 clicks the end of the card's checkbox label through the window's hit test, and logs
#                       `box missed` when the click lands elsewhere.
#   appearance <light|dark>
#                       sets the window's own appearance, as a switch of the system's would, and touches no setting.
#   drawback            reads one frame of the shown Session back and logs `drawback <rrggbb> <aa>`, the first blank
#                       cell's centre, its colour with the alpha divided out.

APP=${APP:-build/selftest/nmux.app}
BIN=$APP/Contents/MacOS/nmux
# The app's tmux sockets land in a short TMUX_TMPDIR of the seam's own, never the author's: a socket path over 104
# bytes fails, so the folder sits in ~/.cache.
export TMUX_TMPDIR="$HOME/.cache/nt-$$"
# Every run reads its config from the seam's own folder, never the author's.
export XDG_CONFIG_HOME="$TMUX_TMPDIR/config"
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
# fresh: an empty private server of the seam's own, no file an earlier run left, and the fallback look in the config.
# The seam starts the server, so its panes run the seam's shell, never a run's fake one, and it outlives its last
# Session. The tmux socket folder stays, so the last check still finds a default socket any run made.
fresh() {
    $T kill-server 2>/dev/null
    mkdir -p "$TMUX_TMPDIR" build/seam
    find "$TMUX_TMPDIR" -mindepth 1 -maxdepth 1 ! -name "tmux-$(id -u)" -exec rm -rf {} +
    config
    $T start-server \; set -s exit-empty off
}
teardown() { [ -n "$PID" ] && alive && stop; PID=; $T kill-server 2>/dev/null; }
finish() { teardown; rm -rf "$TMUX_TMPDIR"; }
trap finish EXIT

# config [<line>...]: the config every later launch reads, the fallback look and the lines given. Runs 1 to 36 check
# the engine in Basic's colours; runs 37 on write their own.
config() { mkdir -p "$XDG_CONFIG_HOME/nmux" && printf '%s\n' "theme = nope" "$@" >"$XDG_CONFIG_HOME/nmux/config"; }
# launch <run> [VAR=value...]: the app, its log in build/seam/<run>.log.
launch() { LOG=build/seam/$1.log; shift; rm -f "$LOG"; env -u TMUX "$@" "$BIN" >"$LOG" 2>&1 & PID=$!; }
# attached: the first Session, the lowest $ID.
attached() { sed -n "s/^selftest: attached \([^ ]*\)$/\1/p" "$LOG" | head -1; }
isAttached() { [ -n "$(attached)" ]; }
hasSession() { $T has-session -t "$1" 2>/dev/null; }
# holds: reads `W H C R w h s` and passes when content W x H points is C x R cells of w x h pixels at scale s,
# within the half point it is rounded up to.
holds() { awk '{ exit !(($3 * $5 / $7 - $1) ^ 2 <= 0.25 && ($4 * $6 / $7 - $2) ^ 2 <= 0.25) }'; }
# plains <format>: the plain clients, without nmux's control client.
plains() { $T list-clients -f "#{==:#{client_control_mode},0}" -F "$1" 2>/dev/null; }
clients() { plains "#{session_id} #{client_control_mode}"; }
controls() { $T list-clients -f "#{client_control_mode}" -F "#{client_name}" 2>/dev/null; }
oneControl() { [ "$(controls | wc -l)" -eq 1 ]; }
noClients() { [ -z "$($T list-clients)" ]; }
