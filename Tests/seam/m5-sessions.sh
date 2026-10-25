# Milestone 5, every Session mirrored: the control client, the Sessions, follow and bell, runs 28 to 31 and 41.

# listed <list>: the last `selftest: sessions` line is <list>.
listed() { [ "$(sed -n "s/^selftest: sessions //p" "$LOG" | tail -1)" = "$1" ]; }
mirrorKept28() { within 3 listed "$want" && alive && oneControl; }
relisted28() { [ "$(grep -c "^selftest: sessions " "$LOG")" -gt "$was" ] && listed "$want"; }
restarted28() { within 3 logged "control restarted" && within 3 relisted28 && alive; }

# Run 28: one control client mirrors the Sessions in $ID order, through every change made outside the app, and
# survives its own Session and a detach. Its own server numbers the Sessions from $0.
run28() {
    $T new-session -d -s api \; new-session -d -s web \; new-session -d -s db
    launch 28
    want='$0:api $1:web $2:db'
    check "three Sessions are listed in \$ID order" within 10 listed "$want"
    check "the app sets mouse on" is on $T show -gv mouse
    check "and set-clipboard on" is on $T show -gv set-clipboard
    check "its control client is the only one" oneControl
    $T new-session -d -s zeta
    want='$0:api $1:web $2:db $3:zeta'
    check "a Session made outside the app is listed last" within 3 listed "$want"
    $T rename-session -t '$0' aaa-api
    want='$0:aaa-api $1:web $2:db $3:zeta'
    check "a rename keeps the place" within 3 listed "$want"
    $T kill-session -t zeta
    want='$0:aaa-api $1:web $2:db'
    check "a killed Session leaves the list" within 3 listed "$want"
    $T kill-session -t '$0'
    want='$1:web $2:db'
    check "killing the control client's own Session keeps the mirror" mirrorKept28
    # A control client that ends within a second of its start ends the app (run 29), so this one waits past it.
    sleep 1
    was=$(grep -c "^selftest: sessions " "$LOG")
    $T detach-client -t "$(controls)"
    check "a detached control client logs its end" within 3 logged "control ended"
    check "and attaches again, keeping its list" restarted28
    check "with one control client" within 3 oneControl
    $T kill-session -t web
    $T kill-session -t db
    check "killing the last Session ends the app" ended
    check "and exits with 0" [ "$status" -eq 0 ]
}

hasControl() { [ -n "$(controls)" ]; }

# Run 29: the server's end ends the app, and so does a control client that ends again within a second of its start.
run29() {
    $T new-session -d -s one
    launch 29
    check "the app starts its control client" within 10 logged "control started"
    $T kill-server
    check "kill-server ends the app" ended
    check "and exits with 0" [ "$status" -eq 0 ]
    $T new-session -d -s one
    launch 29-fast
    within 10 hasControl
    $T detach-client -t "$(controls)"
    check "a control client that ends within a second of its start ends the app" ended
    check "and leaves no client behind" noClients
}

mirror30() { sed -n "s/^selftest: mirror //p" "$LOG" | tail -1; }
# on <n>: the last `mirror` line has $n active. go <line> <n>: the self-test takes the line, a key or
# `goto <shortcut>`, and $n turns active.
on() { [ "$(mirror30 | sed 's/.* active //')" = "\$$1" ]; }
go() { echo "$1" >>"$TMUX_TMPDIR/keys30"; within 3 on "$2"; }
cell30() { grep "^selftest: cell $1 " "$LOG" | tail -1; }
# cluster30 <cell> <cluster>: the cell's last line ends in that cluster.
cluster30() { cell30 "$1" | grep -q "cluster=$2\$"; }
plainSessions() { plains "#{session_id}" | sort | tr "\n" " "; }
plainSizes() { plains "#{client_width}x#{client_height}" | sort -u; }
plainCount() { plains "#{client_name}" | wc -l; }
# readAgain <readbacks before> <cell>: a readback came after those, and the last one found ink in the cell.
readAgain() {
    [ "$(grep -c "^selftest: readback " "$LOG")" -gt "$1" ] \
        && grep "^selftest: readback " "$LOG" | tail -1 | grep -q "^selftest: readback bg ok ink $2 ok"
}
created30() { go "create y" 4 && [ "$(mirror30)" = "$want" ]; }
numbered30() { go "goto session-2" 1 && logged "title nmux: web"; }
pastCount30() { go "goto session-8" 4 && go "goto session-1" 0; }
reattached30() { within 3 logged 'attached $2 again' && logged 'ended $2 attach'; }
backOn30() { plains "#{session_id}" | grep -qxF '$2'; }
resized30() { within 3 is "$grid30" plainSizes && [ "$(plainCount)" -eq 3 ]; }

# Run 30: Sessions. Every Session has a plain client of its own, $0 active at launch. A Session made outside the
# app comes last without the focus; `create` makes its own Session active and names the window after it; the moves
# visit them; killing the active Session passes the focus as the rule says; a detached Session's client attaches again;
# a resize keeps every client at one size; a switch reads back the new Session's own text, and switching back keeps the
# old Session's screen. `api` prints at row 0 and `web` at row 2, so cell 0,2 holds a glyph only in `web`.
run30() {
    $T new-session -d -s api "printf 'hello-api\n'; exec /bin/cat" \; set -t api status off \
        \; new-session -d -s web "printf '\n\nhello-web\n'; exec /bin/cat" \; set -t web status off \
        \; new-session -d -s db
    : >"$TMUX_TMPDIR/keys30"
    launch 30 NMUX_SELFTEST_KEYS="$TMUX_TMPDIR/keys30" NMUX_SELFTEST_CELLS="0,2 0,0"
    want='$0:api $1:web $2:db active $0'
    check "three Sessions show as three pills, \$0 active" within 10 is "$want" mirror30
    check "each Session has one plain client of the app" within 3 is '$0 $1 $2 ' plainSessions
    check "the title names the active Session" logged "title nmux: api"
    $T new-session -d -s x
    want='$0:api $1:web $2:db $3:x active $0'
    check "a Session made outside the app comes last, the active Session kept" within 3 is "$want" mirror30
    want='$0:api $1:web $2:db $3:x $4:y active $4'
    check "create shows its Session" created30
    check "and the title names it" logged "title nmux: y"
    echo "create y" >>"$TMUX_TMPDIR/keys30"
    check "create hands back tmux's refusal" within 3 logged "refused duplicate session: y"
    read30=$(grep -c "^selftest: readback " "$LOG")
    check "a number goes to its Session" numbered30
    check "the switch reads back the new Session's own text" within 5 readAgain "$read30" 0,2
    check "which the Session left never showed" within 3 cluster30 0,0 none
    check "previous goes back" go "goto previous-session" 0
    check "switching back keeps the Session's screen" within 3 cluster30 0,0 68
    check "previous at the first Session wraps to the last" go "goto previous-session" 4
    check "next at the last Session wraps to the first" go "goto next-session" 0
    check "a number past the count goes to the last" pastCount30
    check "Cmd+9 goes to the last Session" go "25 100008 39" 4
    $T kill-session -t y
    want='$0:api $1:web $2:db $3:x active $3'
    check "killing the last, active Session passes the focus to the new last" within 3 is "$want" mirror30
    go "goto session-2" 1
    $T kill-session -t web
    want='$0:api $2:db $3:x active $2'
    check "killing an active Session in the middle passes the focus to the Session now at its place" \
        within 3 is "$want" mirror30
    $T detach-client -t "$(plains "#{session_id} #{client_tty}" | sed -n 's/^\$2 //p')"
    check "a detached Session's client attaches again" reattached30
    check "and is back on its Session" within 3 backOn30
    kill -USR2 "$PID"
    within 3 grep -q "^selftest: content " "$LOG"
    grid30=$(grep "^selftest: resize " "$LOG" | tail -1 | sed "s/^selftest: resize //")
    check "a resize keeps every Session's client at the window's grid" resized30
    $T kill-server
    check "the server's end ends the app" ended
}

mirror31() { sed -n "s/^selftest: mirror //p" "$LOG" | tail -1; }
tty31() { plains "#{session_name} #{client_tty}" | sed -n "s/^$1 //p"; }
ring31() { printf '\a' >"$($T display -p -t "$1" "#{pane_tty}")"; }
bothTtys31() { [ -n "$(tty31 api)" ] && [ -n "$(tty31 web)" ]; }
secondBell31() {
    [ "$(grep -c "^selftest: bell \$1 mark$" "$LOG")" -eq 2 ] && [ "$(grep -c "^selftest: attention$" "$LOG")" -eq 1 ]
}
# followed31 <line>: the app logs that follow, and the mirror turns to $want.
followed31() { within 3 logged "$1" && within 3 is "$want" mirror31; }
noSwitch31() { sleep 0.5; [ "$(mirror31)" = "$want" ] && [ "$(grep -c "^selftest: follow " "$LOG")" -eq 1 ]; }
activeIs31() { [ "$(mirror31 | sed "s/.* active //")" = "$1" ]; }
clientGone31() { [ "$(plainCount)" -eq 2 ] && [ -z "$(tty31 n | grep -xF "$web31")" ]; }

# Run 31: follow and bell. A bell in the hidden Session marks it and, the app never being active, bounces the Dock icon
# once; one in the active Session marks nothing. `switch-client` on a Session's client makes the target's Session active
# and sends the client back, which clears the mark; a Session made and switched to from outside turns active once
# listed; and under `detach-on-destroy off` a Session killed from outside drops its Session and its client, the active
# Session kept. A bell is written straight to the pane's tty, as its program would.
run31() {
    $T new-session -d -s api "exec /bin/cat" \; new-session -d -s web "exec /bin/cat"
    launch 31
    want='$0:api $1:web active $0'
    check "two Sessions, api active" within 10 is "$want" mirror31
    within 3 bothTtys31
    api31=$(tty31 api) web31=$(tty31 web)
    ring31 web
    check "a bell in the hidden Session marks it" within 3 logged 'bell $1 mark'
    check "the app behind another app bounces the Dock icon" within 3 logged attention
    ring31 web
    ring31 api
    check "a bell in the active Session marks nothing" within 3 logged 'bell $0 none'
    check "a second bell before the app was active bounces nothing" secondBell31
    $T switch-client -c "$api31" -t web
    want='$0:api $1:web active $1'
    check "switch-client on api's client follows to web" followed31 "follow api -> web"
    check "and sends the client back to api" within 3 is "$api31" tty31 api
    check "showing web clears its mark" logged 'bell $1 none'
    check "the switch back is no switch" noSwitch31
    $T new-session -d -s n "exec /bin/cat" \; switch-client -c "$web31" -t n
    want='$0:api $1:web $2:n active $2'
    check "a switch to a Session not yet listed makes its Session active once listed" followed31 "follow web -> n"
    check "and web's client is back on web" within 3 is "$web31" tty31 web
    $T switch-client -c "$web31" -t api
    check "a follow to api makes it active" within 3 activeIs31 '$0'
    $T set -g detach-on-destroy off \; kill-session -t web
    want='$0:api $2:n active $0'
    check "a Session killed elsewhere drops its Session and keeps the active one" followed31 'follow dropped $1'
    check "and its client goes" within 3 clientGone31
    $T kill-server
    check "the server's end ends the app" ended
}

reattached41() { within 3 logged 'attached $0 again' && within 3 is '$0' plains "#{session_id}"; }

# Run 41: tmux detaches the Session's client and the control client together, as `detach-client -s` does. The control
# client starts again, and the Session's client attaches again rather than staying dead while it looks alive.
run41() {
    $T new-session -d
    launch 41
    check "the app starts its control client" within 10 logged "control started"
    # A control client that ends within a second of its start ends the app.
    sleep 1.2
    $T detach-client -s '$0'
    check "the control client starts again" within 5 logged "control restarted"
    check "and the Session's client attaches again" reattached41
    check "the app still runs" alive
    kill "$PID"
    check "the app quits on SIGTERM" ended
}
