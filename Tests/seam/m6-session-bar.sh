# Milestone 6, the Session bar: its pills, the New Session field and the Keep-awake cup, runs 32 to 34.

pills32() { sed -n "s/^selftest: pills //p" "$LOG" | tail -1; }
bars32() { grep -c "^selftest: bar 30$" "$LOG"; }
fades32() { sed -n "s/^selftest: fades //p" "$LOG" | tail -1; }
key32() { echo "$1" >>"$TMUX_TMPDIR/keys32"; }
# bar30: every bar height logged is 30 pt.
bar30() { ! grep "^selftest: bar " "$LOG" | grep -vqx "selftest: bar 30"; }
barAbove32() { within 3 over 0 bars32 && bar30; }
shown32() { within 3 is "a b* c" pills32 && within 3 logged "title nmux: b"; }
fadeRight32() { [ "$(pills32 | wc -w)" -eq 10 ] && [ "$(fades32)" = right ]; }
fadeLeft32() { [ "$(pills32 | sed "s/.* //")" = "t10*" ] && [ "$(fades32)" = left ]; }

# Run 32: the Session bar. The bar is 30 pt with two Sessions, with one and with three; the pills follow every Session
# made, killed or rung outside the app; a click on a pill shows its Session; a bell in a hidden Session puts `!` on its
# pill until it is shown. Ten Sessions in a window 900 pt wide fade on the right only; after that resize the bar's right
# end shows the theme's background and the readback finds the first row right under the bar. Cmd+9 brings the last pill
# into view with a fade on the left only.
run32() {
    $T new-session -d -s a "printf 'a\n'; exec /bin/cat" \; new-session -d -s b "exec /bin/cat"
    : >"$TMUX_TMPDIR/keys32"
    launch 32 NMUX_SELFTEST_KEYS="$TMUX_TMPDIR/keys32" NMUX_SELFTEST_CELLS="0,0"
    check "two Sessions show two pills at launch, the first active" within 10 is "a* b" pills32
    check "the bar is 30 pt above the terminal" barAbove32
    $T kill-session -t b
    check "one Session shows one pill, active" within 3 is "a*" pills32
    $T new-session -d -s b "exec /bin/cat"
    $T new-session -d -s c "exec /bin/cat"
    check "a Session made outside the app comes last" within 3 is "a* b c" pills32
    key32 "pill 2"
    check "a click on pill 2 shows its Session" shown32
    check "the click lands on the pill" not grep -q "^selftest: pill .* missed$" "$LOG"
    printf '\a' >"$($T display -p -t '=c:' "#{pane_tty}")"
    check "a bell in a hidden Session puts the dot on its pill" within 3 is "a b* c!" pills32
    key32 "pill 3"
    check "showing it clears the dot" within 3 is "a b c*" pills32
    $T kill-session -t b \; kill-session -t c
    check "one Session again keeps one pill" within 3 is "a*" pills32
    check "and the bar is still 30 pt" bar30
    for s in 2 3 4 5 6 7 8 9 10; do $T new-session -d -s "t$s" "printf 't$s\n'; exec /bin/cat"; done
    key32 "goto session-1"
    read32=$(grep -c "^selftest: readback " "$LOG")
    key32 "width 900"
    check "ten Sessions in a narrow window fade on the right only" within 5 fadeRight32
    check "after the resize the readback finds the first row right under the bar" within 5 readAgain "$read32" 0,0
    key32 "barback"
    check "and the bar's right end shows the theme's background" within 3 logged "barback bg ok"
    key32 "25 100008 39"
    check "Cmd+9 brings the last pill into view, with a fade on the left only" within 3 fadeLeft32
    check "and the bar is still 30 pt" bar30
    $T kill-server
    check "the server's end ends the app" ended
}

pills33() { sed -n "s/^selftest: pills //p" "$LOG" | tail -1; }
key33() { echo "$1" >>"$TMUX_TMPDIR/keys33"; }
fields33() { grep -c "^selftest: field $1$" "$LOG"; }
keptField33() { [ "$(fields33 open)" -eq 1 ] && hasSession =build; }
numbered33() { [ "$(fields33 closed)" -eq 2 ] && pills33 | grep -qx 'api web build [0-9][0-9]*\*'; }
otherLast33() { pills33 | grep -q " other\$"; }
keptOther33() { within 3 otherLast33 && [ "$(fields33 closed)" -eq 2 ]; }
build2Active33() { pills33 | grep -q " build2\*\$"; }
build2_33() { within 3 hasSession =build2 && within 3 build2Active33; }

# Run 33: the New Session field. Cmd+T opens it, a second Cmd+T keeps its text, and Return makes the typed Session's
# pill last and active, the keys never reaching the terminal; a click on the plus and Return let tmux number the
# Session; a name tmux refuses keeps the field open with tmux's error in a tip; a Session made elsewhere keeps the field
# and its text; Escape drops it and makes nothing; the pointer resting on the plus shows "New Session" after half a
# second.
run33() {
    $T new-session -d -s api "exec /bin/cat" \; new-session -d -s web "exec /bin/cat"
    : >"$TMUX_TMPDIR/keys33"
    launch 33 NMUX_SELFTEST_KEYS="$TMUX_TMPDIR/keys33"
    check "two Sessions, api active" within 10 is "api* web" pills33
    key33 "17 100008 74"
    check "Cmd+T opens the field" within 3 is 1 fields33 open
    keys33=$(grep -c "^selftest: key " "$LOG")
    key33 "type bu"
    key33 "goto new-session"
    key33 "type ild"
    key33 "return"
    check "Return closes the field" within 3 is 1 fields33 closed
    check "a second Cmd+T kept the field and its text" keptField33
    check "build's pill comes last and active" within 3 is "api web build*" pills33
    check "keys typed in the field never reach the terminal" is "$keys33" grep -c "^selftest: key " "$LOG"
    key33 "plus"
    check "a click on the plus opens the field" within 3 is 2 fields33 open
    key33 "return"
    check "an empty name makes a Session tmux numbers, its Session active" within 3 numbered33
    key33 "17 100008 74"
    key33 "type build"
    key33 "return"
    check "a second build is refused with tmux's own text" \
        within 3 grep -q "^selftest: field refused duplicate session: build" "$LOG"
    check "the refusal shows in a tip" grep -q "^selftest: tip duplicate session: build" "$LOG"
    check "and the field stays open" is 2 fields33 closed
    $T new-session -d -s other "exec /bin/cat"
    check "a Session made elsewhere keeps the field" keptOther33
    key33 "type 2"
    key33 "return"
    check "the kept text and one more character make build2" build2_33
    key33 "17 100008 74"
    key33 "type tmp"
    key33 "escape"
    check "Escape drops the field" within 3 is 4 fields33 closed
    check "and makes no Session" not hasSession =tmp
    key33 "plus rest"
    sleep 0.3
    check "the plus's tip waits half a second" not logged "tip New Session"
    check "then New Session shows" within 2 logged "tip New Session"
    $T kill-server
    check "the server's end ends the app" ended
}

key34() { echo "$1" >>"$TMUX_TMPDIR/keys34"; }
held34() {
    pmset -g assertions | grep "pid $PID(" | grep "PreventUserIdleSystemSleep" \
        | grep -q 'named: "nmux keeps the Mac awake"'
}
off34() { within 10 logged "pills a*" && logged "cup off"; }
onAgain34() { within 3 is 2 grep -c "^selftest: cup on " "$LOG" && held34; }
heldBy34() { pmset -g assertions | grep "pid $pid34(" | grep -q "nmux keeps the Mac awake"; }

# Run 34: the Keep-awake cup. It starts off with no assertion of the app's in `pmset -g assertions`; a click holds
# "nmux keeps the Mac awake" under PreventUserIdleSystemSleep and washes the window in the accent, gone 1 s later; the
# next click releases it; the pointer resting on it shows the state's tip, after a click the new state's; on, then
# quitting, releases it and leaves no such assertion.
run34() {
    $T new-session -d -s a "exec /bin/cat"
    : >"$TMUX_TMPDIR/keys34"
    launch 34 NMUX_SELFTEST_KEYS="$TMUX_TMPDIR/keys34"
    check "the cup starts off" off34
    check "and the app holds no assertion" not held34
    key34 "cup"
    check "a click turns it on with the assertion's ID" within 3 grep -q "^selftest: cup on [0-9][0-9]*$" "$LOG"
    check "the click lands on the cup" not logged "cup missed"
    key34 "washback"
    check "pmset lists it under PreventUserIdleSystemSleep" held34
    check "the window right after is tinted toward the accent" within 3 logged "washback tinted"
    sleep 1
    key34 "washback"
    check "and 1 s later is not" within 3 logged "washback plain"
    check "the pointer resting on after the click shows the new state's tip" \
        logged "tip The Mac stays awake while nmux runs. Click to let it sleep."
    key34 "cup"
    check "the next click turns it off" within 3 is 2 grep -c "^selftest: cup off$" "$LOG"
    check "and pmset no longer lists it" within 3 not held34
    key34 "cup rest"
    sleep 0.3
    check "the cup's tip waits half a second" not logged "tip Click to keep the Mac awake while nmux runs."
    check "then says what a click will do" within 2 logged "tip Click to keep the Mac awake while nmux runs."
    key34 "cup"
    check "on again" onAgain34
    pid34=$PID
    kill "$PID"
    check "the app quits on SIGTERM" ended
    check "quitting releases the hold" logged "cup released"
    check "and leaves no assertion of its own" not heldBy34
}
