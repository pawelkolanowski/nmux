# Milestone 7, closing: a Session and nmux, runs 35 and 36.

pills35() { sed -n "s/^selftest: pills //p" "$LOG" | tail -1; }
key35() { echo "$1" >>"$TMUX_TMPDIR/keys35"; }
count35() { grep -c "^selftest: $1$" "$LOG"; }
stillA35() { within 3 is "a* b" pills35 && ! logged "answer kill"; }
renamed35() { within 3 is 3 count35 "answer cancel" && within 3 is "a c*" pills35; }
closeAsks35() { within 3 logged 'ask session $0' && ! logged "close 1 missed"; }
binKills35() { within 3 is 2 count35 "answer kill" && ! logged "bin missed"; }

# Run 35: closing a Session. Cmd+W on the active b asks on its pill, which washes toward the danger colour, and the
# Session still runs; keys go nowhere and a second Cmd+W does nothing while it asks; Escape cancels; a click on the pill
# a cancels and still shows a; a rename elsewhere drops the prompt; Return kills b's Session, a turns active with one
# client of its own; a click on a's close mark and on the bin kills a, and the app quits with the last Session.
run35() {
    $T new-session -d -s a "exec /bin/cat" \; new-session -d -s b "exec /bin/cat"
    : >"$TMUX_TMPDIR/keys35"
    launch 35 NMUX_SELFTEST_KEYS="$TMUX_TMPDIR/keys35"
    check "two Sessions, a active" within 10 is "a* b" pills35
    key35 "pill 2"
    within 3 is "a b*" pills35
    key35 "13 100008 77"
    check "Cmd+W asks on b's pill" within 3 logged 'ask session $1'
    check "and b's Session still runs" hasSession =b
    key35 "washback pill 2"
    check "the asking pill is tinted toward the danger colour" within 3 logged "washback tinted"
    keys35=$(grep -c "^selftest: key " "$LOG")
    key35 "type x"
    key35 "13 100008 77"
    key35 "escape"
    check "Escape cancels" within 3 is 1 count35 "answer cancel"
    check "keys while it asks never reach the terminal" is "$keys35" grep -c "^selftest: key " "$LOG"
    check "and a second Cmd+W asks nothing" is 1 count35 'ask session $1'
    check "tmux ls still lists b" hasSession =b
    key35 "13 100008 77"
    within 3 is 2 count35 'ask session $1'
    key35 "pill 1"
    check "a click on the pill a cancels" within 3 is 2 count35 "answer cancel"
    check "and still shows a" stillA35
    key35 "pill 2"
    within 3 is "a b*" pills35
    key35 "13 100008 77"
    within 3 is 3 count35 'ask session $1'
    $T rename-session -t b c
    check "a rename elsewhere drops the prompt" renamed35
    key35 "13 100008 77"
    within 3 is 4 count35 'ask session $1'
    key35 "return"
    check "Return kills" within 3 logged "answer kill"
    check "tmux ls no longer lists the Session" within 3 not hasSession '$1'
    check "a turns active" within 3 is "a*" pills35
    check "with one client of its own" within 3 is a plains "#{session_name}"
    key35 "close 1"
    check "a click on a's close mark asks on its pill" closeAsks35
    key35 'bin $0'
    check "a click on the bin kills" binKills35
    check "the app quits with the last Session" ended
    check "and tmux ls no longer lists a" not hasSession =a
}

key36() { echo "$1" >>"$TMUX_TMPDIR/keys36"; }
keyAll36() { echo "$1" >>"$TMUX_TMPDIR/keys36-all"; }
count36() { grep -c "^selftest: $1$" "$LOG"; }
pills36() { sed -n "s/^selftest: pills //p" "$LOG" | tail -1; }
sessions36() { $T ls -F "#{session_name}" | tr "\n" " "; }
cancelAll36() { within 3 logged "answer cancel all" && ! logged "box missed"; }
noSession36() { [ -z "$($T ls 2>/dev/null)" ]; }

# Run 36: Closing nmux. Cmd+Q asks on the card, which draws its default button in the accent; keys go nowhere and
# a second Cmd+Q asks nothing while it shows; Escape cancels, the app still runs and the button's place shows no accent.
# The close button asks the same. Cmd+Q then Return quits and leaves a and b running with no client of the app's.
# Cmd+Shift+W with the box ticked, then Escape, cancels; again with the box ticked from the keyboard, Return kills every
# Session. SIGTERM quits without asking.
run36() {
    $T new-session -d -s a "exec /bin/cat" \; new-session -d -s b "exec /bin/cat"
    : >"$TMUX_TMPDIR/keys36"
    launch 36 NMUX_SELFTEST_KEYS="$TMUX_TMPDIR/keys36"
    check "two Sessions" within 10 is "a* b" pills36
    key36 "12 100008 71"
    check "Cmd+Q asks on the closing card" within 3 logged "ask closing"
    sleep 0.3
    key36 "washback card"
    check "the card's default button shows in the accent" within 3 logged "washback tinted"
    keys36=$(grep -c "^selftest: key " "$LOG")
    key36 "type x"
    key36 "12 100008 71"
    key36 "escape"
    check "Escape cancels" within 3 logged "answer cancel"
    check "keys while it shows never reach the terminal" is "$keys36" grep -c "^selftest: key " "$LOG"
    check "and a second Cmd+Q asks nothing" is 1 count36 "ask closing"
    check "the app still runs" alive
    key36 "washback card"
    check "and the card's button no longer shows there" within 3 logged "washback plain"
    key36 "close button"
    check "the close button asks the same" within 3 is 2 count36 "ask closing"
    key36 "escape"
    within 3 is 2 count36 "answer cancel"
    key36 "12 100008 71"
    within 3 is 3 count36 "ask closing"
    key36 "return"
    check "Return closes" within 3 logged "answer close"
    check "the app quits" ended
    check "tmux ls still lists a and b" is "a b " sessions36
    check "with no client of the app's left" within 3 noClients
    : >"$TMUX_TMPDIR/keys36-all"
    launch 36-all NMUX_SELFTEST_KEYS="$TMUX_TMPDIR/keys36-all"
    within 10 is 2 grep -c "^selftest: attached " "$LOG"
    keyAll36 "13 12000a 57"
    check "Cmd+Shift+W asks on the closing card" within 3 logged "ask closing"
    keyAll36 "box"
    keyAll36 "escape"
    check "Escape with the box ticked cancels" cancelAll36
    check "and kills nothing" is "a b " sessions36
    keyAll36 "13 12000a 57"
    within 3 is 2 grep -c "^selftest: ask closing$" "$LOG"
    # Tab moves the focus to the box, its first part, and Space ticks it.
    keyAll36 "48 0 09"
    keyAll36 "49 0 20"
    keyAll36 "return"
    check "the box ticked with Tab and Space, Return kills all" within 3 logged "answer close all"
    check "the app quits" ended
    check "and the server holds no Session" within 3 noSession36
    $T new-session -d -s a "exec /bin/cat"
    launch 36-term
    within 10 logged "control started"
    kill "$PID"
    check "SIGTERM quits" ended
    check "without asking" not logged "ask closing"
    check "and leaves a running" hasSession =a
}
