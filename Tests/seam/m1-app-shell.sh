# Milestone 1, the app shell: runs 1 to 10 and 40.

startedOneControl() { within 3 logged "control started" && oneControl; }
ptyControls() {
    [ "$(ps -o tty= -p "$(plains "#{client_pid}")" | tr -d " ")" = "$(plains "#{client_tty}" | sed "s#^/dev/##")" ]
}
wholePixels() { echo "$cell" | grep -qE "^[0-9]+ [0-9]+ baseline [0-9]+ scale [0-9.]+$"; }
contentHolds() { echo "$cell $grid" | awk '{ print $10, $11, $7, $8, $1, $2, $6 }' | holds; }
topEdge() {
    echo "$(sed -n "s/^selftest: window //p" "$LOG") $(sed -n "s/^selftest: visible //p" "$LOG")" \
        | awk '{ exit !(($2 + $4 - $6 - $8) ^ 2 <= 1) }'
}
fallbackFace() {
    f=$(sed -n "s/^selftest: face U+4E2D //p" "$LOG")
    [ -n "$f" ] && [ "$f" != none ] && [ "${f#.}" != LastResort ] && ! logged "face U+0041 $f"
}

# Run 1: an empty server gets one Session and one plain client on it, at the window's grid. The server
# starts empty and logs every size it sets for a client or a window: tmux sets the client's once on the attach.
run1() {
    $T start-server \; set -s exit-empty off \
        \; set-hook -g client-resized "run-shell 'echo client #{client_width} #{client_height} >>$TMUX_TMPDIR/sizes'" \
        \; set-hook -g window-resized "run-shell 'echo window #{window_width} #{window_height} >>$TMUX_TMPDIR/sizes'"
    launch 1
    check "the app logs its launch" within 10 logged launched
    check "the app logs its placement" within 10 grep -q "^selftest: visible " "$LOG"
    check "the app calls libghostty-vt" grep -q "^selftest: libghostty-vt [0-9]*\.[0-9]*\.[0-9]*$" "$LOG"
    check "the app attaches" within 10 grep -q "^selftest: attached " "$LOG"
    check "the app logs the tmux it found" grep -q "^selftest: tmux /.*/tmux [0-9]" "$LOG"
    check "an empty server gets one Session" is "$(attached)" $T list-sessions -F "#{session_id}"
    check "one plain client is attached to it" within 3 is "$(attached) 0" clients
    check "and one control client" startedOneControl
    check "the pty is the client's controlling terminal" ptyControls
    # `cell W H baseline B scale S` and `grid C R content W H`, with the x's as spaces.
    cell=$(sed -n "s/^selftest: cell //p" "$LOG" | tr x ' ')
    grid=$(sed -n "s/^selftest: grid //p" "$LOG" | tr x ' ')
    check "the cell is measured in whole pixels" wholePixels
    check "the content holds the grid times the cell, within half a point" contentHolds
    # The seam cannot move the pointer, so it checks the screen under the pointer as it is now.
    check "the window's top edge is the visible frame's top" topEdge
    check "tmux sees the client at the logged grid" \
        is "$(echo "$grid" | cut -d " " -f 1-2)" plains "#{client_width} #{client_height}"
    seen="client $(echo "$grid" | cut -d " " -f 1-2)"
    check "tmux sets the client to the logged grid on the attach" within 3 grep -qxF "$seen" "$TMUX_TMPDIR/sizes"
    check "and never to another size, nor resizes its window" not grep -vxF "$seen" "$TMUX_TMPDIR/sizes"
    check "SF Mono draws a Latin letter" not logged "face U+0041 none"
    check "a fallback face other than SF Mono draws 中" fallbackFace
    check "LastResort never stands in for a glyph" logged "face U+10FFFD none"
    kill "$PID"
    check "the app quits on SIGTERM" ended
    check "and exits with 0" [ "$status" -eq 0 ]
    check "the Session survives" $T has-session -t "$(attached)"
    check "and no client of the app stays on the server" within 3 noClients
}

clientsInOrder() { clients | sort | tr "\n" " "; }
keptList() { within 3 logged 'sessions $1:1' && alive; }

# Run 2: $0 and $1 each get a plain client, $0 first. Killing $0, which the control client sits on too, keeps the
# app; killing the last one ends it.
run2() {
    # The server outlives its last Session, so only the app's own rule ends the app.
    $T new-session -d \; new-session -d \; set -s exit-empty off
    launch 2
    check "the app attaches to the lowest \$ID first" within 10 is '$0' attached
    check "and a client to each Session" within 3 is '$0 0 $1 0 ' clientsInOrder
    within 10 logged "control started"
    $T kill-session -t '$0'
    check "killing the Session the control client sits on keeps the app and its list" keptList
    $T kill-session -t '$1'
    check "killing the last Session ends the app" ended
    check "and exits with 0" [ "$status" -eq 0 ]
}

# running <command line>: a process runs that exact command line.
running() { ps -axo command | LC_ALL=C grep -aq "^$1\$"; }

# Run 3: a login shell that hangs costs at most 2 s; the known paths still find tmux.
run3() {
    printf '#!/bin/sh\nsleep 10\n' >"$TMUX_TMPDIR/hang" && chmod +x "$TMUX_TMPDIR/hang"
    launch 3 SHELL="$TMUX_TMPDIR/hang"
    check "a hanging login shell still attaches within 3 s" within 3 isAttached
    check "the hung shell is gone, with its children" not running "sleep 10"
    kill "$PID"
    check "the app quits on SIGTERM" ended
}

# Runs 4 to 10 hide the known paths; a login shell that searches only $FAKE_PATH decides what exists.
# `fake <run> <name> <body>` writes an executable into that run's own bin folder.
REAL=$(command -v tmux)
bin() { echo "$TMUX_TMPDIR/r$1"; }
fake() {
    mkdir -p "$(bin $1)" && printf '#!/bin/sh\n%s\n' "$3" >"$(bin $1)/.$2" && chmod +x "$(bin $1)/.$2" \
        && mv "$(bin $1)/.$2" "$(bin $1)/$2"
}
hidden() {
    printf '#!/bin/sh\nPATH="$FAKE_PATH" exec /bin/sh -c "$3"\n' >"$TMUX_TMPDIR/shell" && chmod +x "$TMUX_TMPDIR/shell"
    r=$1; shift; mkdir -p "$(bin $r)"
    launch $r SHELL="$TMUX_TMPDIR/shell" FAKE_PATH="$(bin $r):/usr/bin:/bin" NMUX_SELFTEST_NO_KNOWN_PATHS=1 "$@"
}
carded() { within 10 logged "card $1"; }

# Run 4: no tmux and no brew show the card with the commands; Restart after a tmux appears attaches.
run4() {
    hidden 4 NMUX_SELFTEST_PRESS=restart
    check "no tmux and no brew show the missing-no-brew card" carded missing-no-brew
    check "the failure is logged" logged "failure missing"
    check "the app stays open on the card" alive
    fake 4 tmux "exec $REAL \"\$@\""
    check "Restart after tmux appears attaches" within 10 isAttached
    kill "$PID"
    check "the app quits on SIGTERM" ended
}

# Run 5: a tmux older than 3.4 shows the too-old card.
run5() {
    fake 5 tmux 'echo tmux 3.2a'
    hidden 5
    check "tmux 3.2a shows the too-old card" carded too-old-no-brew
    check "the failure names the version found" logged "failure too-old $(bin 5)/tmux 3.2a"
    kill "$PID"
    check "the app quits from the card on SIGTERM" ended
    check "and exits with 0" [ "$status" -eq 0 ]
}

# Run 6: Install runs brew; a brew that leaves a working tmux behind ends in an attach.
run6() {
    fake w tmux "exec $REAL \"\$@\""
    fake 6 brew "echo \"==> \$*\"; cp $(bin w)/tmux $(bin 6)/tmux"
    hidden 6 NMUX_SELFTEST_PRESS=install
    check "no tmux with brew shows the missing-brew card" carded missing-brew
    check "the self-test presses Install" within 3 logged "press install"
    check "the card shows the install" carded installing
    check "a brew that succeeds ends in an attach" within 10 isAttached
    kill "$PID"
    check "the app quits on SIGTERM" ended
}

# Run 7: a brew that fails shows its error.
run7() {
    fake 7 brew 'echo "Error: no bottle" >&2; exit 1'
    hidden 7 NMUX_SELFTEST_PRESS=install
    check "a brew that fails shows the install-failed card" carded install-failed
    kill "$PID"
    check "the app quits on SIGTERM" ended
}

# Run 8: a tmux whose server will not start shows the server card.
run8() {
    fake 8 tmux 'for a; do [ "$a" = -V ] && { echo tmux 3.5; exit 0; }; done; echo "no server: boom" >&2; exit 1'
    hidden 8
    check "a server that will not start shows the server card" carded server
    check "the failure carries tmux's error" logged "failure server no server: boom"
    kill "$PID"
    check "the app quits on SIGTERM" ended
}

waits9() { logged "ended $(attached) wait"; }

# Run 9: a Session whose client fails within a second of its start keeps tmux's error on screen, with no card; a key
# tries again. Only the plain client fails; the control client attaches.
run9() {
    # A Session waits on the server, so the plain client attaches to it rather than making its own.
    $T new-session -d
    tmux9="case \"\$*\" in *-C*) exec $REAL \"\$@\";; *attach-session*) echo 'no attach: boom'; exit 1;; esac; exec"
    tmux9="$tmux9 $REAL \"\$@\""
    fake 9 tmux "$tmux9"
    : >"$TMUX_TMPDIR/keys9"
    hidden 9 NMUX_SELFTEST_SCREEN="$TMUX_TMPDIR/screen9" NMUX_SELFTEST_KEYS="$TMUX_TMPDIR/keys9"
    check "a client that fails within a second waits" within 10 waits9
    check "with tmux's error on screen" within 3 grep -qsF "no attach: boom" "$TMUX_TMPDIR/screen9"
    check "and no card" not grep -q "^selftest: card " "$LOG"
    echo "0 0 61" >>"$TMUX_TMPDIR/keys9"
    check "a key attaches again" within 3 logged "attached $(attached) again"
    check "and its failure waits again" within 3 is 2 grep -c "^selftest: ended .* wait\$" "$LOG"
    kill "$PID"
    check "the app quits on SIGTERM" ended
}

# Run 10: quitting during the install ends brew.
run10() {
    fake 10 brew 'echo working; exec sleep 31'
    hidden 10 NMUX_SELFTEST_PRESS=install
    check "the install starts" carded installing
    kill "$PID"
    check "the app quits on SIGTERM during the install" ended
    check "brew ends with it" within 3 not running "sleep 31"
}

utf8Line40() { grep -qF "zażółć →" "$TMUX_TMPDIR/screen40"; }

# Run 40: launched as from the Dock, with no locale variable, the app's client is UTF-8, and a pane's non-ASCII line
# reaches the screen intact, never as `_`.
run40() {
    $T new-session -d "/usr/bin/printf 'zażółć →\n'; exec /bin/cat"
    launch 40 -u LANG -u LC_ALL -u LC_CTYPE NMUX_SELFTEST_SCREEN="$TMUX_TMPDIR/screen40"
    check "the app attaches" within 10 isAttached
    check "its client is UTF-8" within 3 is 1 plains "#{client_utf8}"
    check "a pane's non-ASCII line reaches the screen intact" within 5 utf8Line40
    kill "$PID"
    check "the app quits on SIGTERM" ended
}
