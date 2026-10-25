# Milestone 4, input: keys, text input, the mouse, the selection, paste and OSC 52, runs 19 to 27.

keyLines() { grep -c "^selftest: key \|^selftest: shortcut " "$LOG"; }
# press <keycode> <flags> <chars>, then waits for the key's log line; sent <keycode> <hex> checks the last one.
press() { n=$(keyLines); echo "$1 $2 $3" >>"$TMUX_TMPDIR/keys"; within 3 over "$n" keyLines; }
sent() { grep "^selftest: key $1 " "$LOG" | tail -1 | grep -q " -> $2\$"; }
keysShow() { $T capture-pane -p -t keys | grep -qF "$1"; }
history19() { $T display -p -t keys "#{history_size}"; }

# Run 19: keys. The pane runs `cat -v` on a raw tty, so it shows what it gets. Each line the seam adds to the keys file
# is one key the self-test presses: `<keycode> <flags> <utf8 hex or ->`; each key the view sends logs its bytes.
run19() {
    $T new-session -d -s keys "/bin/stty raw -echo; exec /bin/cat -v" \; set -t keys status off
    : >"$TMUX_TMPDIR/keys"
    launch 19 NMUX_SELFTEST_KEYS="$TMUX_TMPDIR/keys" NMUX_SELFTEST_OPTION_AS_ALT=left
    check "the app attaches" within 10 isAttached
    within 10 logged "probe hold"
    press 0 0 61
    check "typing a logs 61" sent 0 61
    check "and the pane shows a" within 3 keysShow a
    press 8 40001 03
    check "Ctrl+C logs 03" sent 8 03
    press 53 0 1b
    check "Escape logs 1b" sent 53 1b
    # tmux turns on application cursor keys for every client it attaches, so the encoder, which takes the terminal's
    # modes, makes ESC O A where a bare one makes ESC [ A.
    press 126 a00000 ef9c80
    check "Up logs ESC O A under tmux's application cursor keys" sent 126 1b4f41
    press 11 80020 e288ab
    check "with option-as-alt left, the left Option and b log ESC b" sent 11 1b62
    press 123 b00008 ef9c82
    check "Cmd+Left logs Ctrl+A" sent 123 01
    press 17 100008 74
    check "Cmd+T logs the new-session shortcut" logged "shortcut new-session"
    check "and sends nothing to the PTY" not grep -q "^selftest: key 17 " "$LOG"
    # Cmd+T opened the New Session field, which holds the focus until Escape drops it.
    echo "escape" >>"$TMUX_TMPDIR/keys"
    check "Escape drops the field Cmd+T opened" within 3 logged "field closed"
    press 24 100008 3d
    check "Cmd+= reaches the encoder, which makes no bytes of it as Ghostty does" sent 24 none
    $T respawn-pane -k -t keys "/usr/bin/seq 1 500; /bin/stty raw -echo; exec /bin/cat -v"
    check "the pane has scrollback" within 3 over 0 history19
    press 40 100008 6b
    check "Cmd+K logs the clear shortcut" logged "shortcut clear"
    check "and empties the active pane's history" within 3 is 0 history19
    check "then Ctrl+L reaches the pane, so the shell redraws its prompt" within 3 keysShow "^L"
    $T kill-session -t keys
    check "killing the Session ends the app" ended
    check "and exits with 0" [ "$status" -eq 0 ]
}

# Run 20: with option-as-alt false, the left Option types: Option+L on a Polish layout logs ł. The fixture is the
# characters Polish Pro gives the event, since switching the author's own input source is not the seam's to do.
run20() {
    $T new-session -d -s polish "/bin/stty raw -echo; exec /bin/cat -v" \; set -t polish status off
    : >"$TMUX_TMPDIR/keys"
    launch 20 NMUX_SELFTEST_KEYS="$TMUX_TMPDIR/keys"
    check "the app attaches" within 10 isAttached
    within 10 logged "probe hold"
    press 37 80020 c582
    check "Option+L logs the UTF-8 of ł" sent 37 c582
    $T kill-session -t polish
    check "killing the Session ends the app" ended
}

# Each key or client call waits for its key, shortcut, preedit or commit line.
lines21() { grep -c "^selftest: \(key\|shortcut\|preedit\|commit\|rect\)\( \|\$\)" "$LOG"; }
cleared21() { grep -c "^selftest: preedit\$" "$LOG"; }
press21() { n=$(lines21); echo "$*" >>"$TMUX_TMPDIR/keys"; within 3 over "$n" lines21; }
pane21() { $T capture-pane -p -t text | head -1; }
got21() { [ "$(xxd -p "$TMUX_TMPDIR/typed" | tr -d '\n')" = "$1" ]; }
# received21 <hex> <text>: the pane got exactly those bytes and shows that text on its first row.
received21() { within 3 got21 "$1" && [ "$(pane21)" = "$2" ]; }
dropped21() { ! grep -q "^selftest: key 53 " "$LOG" && sleep 0.5 && got21 c3a9; }
marked21() { [ "$(field 1,0 cluster)" = 306b ] && [ "$(field 1,0 deco)" = "underline:#$fg" ]; }
lastRect21() { sed -n "s/^selftest: rect //p" "$LOG" | tail -1; }
ownGlyph21() { [ "$(field 1,0 cluster)" = 65e5 ] && [ "$(field 1,0 deco)" = none ]; }

# Run 21: text input. The pane's `tee` shows what it gets and keeps the bytes in a file. A synthetic key never reaches
# the input source while the app is not active, so a key's fourth field is the fixture of what the US layout's text
# system does with it: Option+E marks ´ and the next E inserts é. The client's own calls, `mark`, `insert` and `rect`,
# stand for an IME. The first named cell is where the cursor waits after é, so the readback runs once the marked text
# draws there, and again after the commit.
run21() {
    $T new-session -d -s text "/bin/stty raw -echo; exec /usr/bin/tee $TMUX_TMPDIR/typed" \; set -t text status off
    : >"$TMUX_TMPDIR/keys"
    launch 21 NMUX_SELFTEST_KEYS="$TMUX_TMPDIR/keys" NMUX_SELFTEST_CELLS="1,0"
    check "the app attaches" within 10 isAttached
    within 10 logged "probe hold"
    fg=$([ "$(sed -n "s/^selftest: background system #//p" "$LOG")" = ffffff ] && echo 000000 || echo ffffff)
    press21 14 80020 - mark:c2b4
    check "Option+E marks ´" logged "preedit c2b4"
    check "and its key sends nothing" sent 14 none
    press21 14 0 65 insert:c3a9
    check "the next E commits é" within 3 logged "commit c3a9"
    check "and the pane receives é and nothing else" received21 c3a9 é
    press21 14 80020 - mark:c2b4
    was=$(cleared21)
    press21 53 0 1b mark:
    check "Escape drops the marked text" over "$was" cleared21
    check "and sends nothing" dropped21
    press21 mark e381abe381bb
    check "an IME's marked text is logged" logged "preedit e381abe381bb"
    check "and drawn at the cursor, underlined, in place of the cell's own" within 3 marked21
    check "with no cursor over it, as Ghostty draws marked text" within 3 is none cursor
    check "the readback finds the marked text's ink in the cursor's cell" \
        within 5 grep -q "^selftest: readback bg ok ink 1,0 ok " "$LOG"
    cell=$(sed -n "s/^selftest: cell \([0-9]*\)x\([0-9]*\) baseline [0-9]* scale \([0-9.]*\)$/\1 \2 \3/p" "$LOG")
    rect=$(echo $cell | awk '{ printf "%g 0 0 %g", 1.5 * $1 / $3, $2 / $3 }')
    press21 rect
    check "the candidate window's rect is the cursor's cell, from its middle, with no width for an empty range" \
        is "$rect" lastRect21
    press21 insert e697a5e69cac
    check "the IME's commit is logged once" within 3 is 1 grep -c "^selftest: commit e697a5e69cac\$" "$LOG"
    check "and the pane receives 日本 after é" received21 c3a9e697a5e69cac é日本
    check "the readback finds ink in the cursor's cell again after the commit" \
        within 5 over 1 grep -c "^selftest: readback bg ok ink 1,0 ok " "$LOG"
    check "the cursor's cell returns to its own glyph" within 3 ownGlyph21
    check "and the cursor is drawn again" within 3 not is none cursor
    $T kill-session -t text
    check "killing the Session ends the app" ended
}

# Run 22: with option-as-alt true, Option+E goes through the text system without Option and sends ESC e, with no marked
# text.
run22() {
    $T new-session -d -s alt "/bin/stty raw -echo; exec /bin/cat -v" \; set -t alt status off
    : >"$TMUX_TMPDIR/keys"
    launch 22 NMUX_SELFTEST_KEYS="$TMUX_TMPDIR/keys" NMUX_SELFTEST_OPTION_AS_ALT=true
    check "the app attaches" within 10 isAttached
    within 10 logged "probe hold"
    press 14 80020 c499
    check "Option+E logs ESC e" sent 14 1b65
    check "and no marked text" not grep -q "^selftest: preedit" "$LOG"
    $T kill-session -t alt
    check "killing the Session ends the app" ended
}

reports23() { grep -c "^selftest: \(mouse\|open\) " "$LOG"; }
# act23 <line>: waits for a report; quiet23 <line>: waits a second and passes when none came.
act23() { n=$(reports23); echo "$*" >>"$TMUX_TMPDIR/keys"; within 3 over "$n" reports23; }
quiet23() { n=$(reports23); echo "$*" >>"$TMUX_TMPDIR/keys"; sleep 1; [ "$(reports23)" -eq "$n" ]; }
active23() { $T display -p -t mouse '#{pane_index}'; }
pointer23() {
    n=$(grep -c "^selftest: pointer " "$LOG"); echo pointer >>"$TMUX_TMPDIR/keys"
    within 3 over "$n" grep -c '^selftest: pointer ' "$LOG"
    grep "^selftest: pointer " "$LOG" | tail -1 | sed "s/^selftest: pointer //"
}
pressReleased23() {
    logged "mouse press left 60,5 -> 1b5b3c303b36313b364d" \
        && within 3 logged "mouse release left 60,5 -> 1b5b3c303b36313b366d"
}
fiveDown23() { sleep 0.5; [ "$(grep -c "^selftest: mouse press five " "$LOG")" -eq 5 ]; }
# clicked23 <button> <hex>: a click with that button at 10,5 logs its press as those bytes.
clicked23() { act23 click "$1" 10,5 0 && logged "mouse press $1 10,5 -> $2"; }
underlined23() { field 42,0 deco | grep -q "^underline:"; }
# opens23 <cell> <url>: a Cmd+click there opens the url.
opens23() { act23 click left "$1" 100008 && logged "open $2"; }

# Run 23: the mouse. tmux's mouse is on, and the window keeps 80 x 24, so the right pane starts at column 41. The left
# pane prints a line, the right one an OSC 8 link, plain text and a URL, and both then run `cat`. A mouse line in the
# keys file is one event the self-test hands the view: `click <button> <col>,<row> <flags>`, `move <col>,<row> <flags>`
# or `wheel <points> <precise> <count> <flags>`, and `pointer` logs the pointer; each report logs its bytes, and each
# link opened its target.
run23() {
    cat >"$TMUX_TMPDIR/links" <<'EOF'
/usr/bin/printf '\033]8;;https://example.com/x\033\\link\033]8;;\033\\ plain\nsee https://example.org/y\n'
EOF
    $T new-session -d -s mouse "/usr/bin/printf 'left\n'; exec /bin/cat" \; set -t mouse status off \
        \; set -t mouse mouse on \
        \; set -t mouse window-size manual \; resize-window -t mouse -x 80 -y 24 \
        \; split-window -h -t mouse "/bin/sh $TMUX_TMPDIR/links; exec /bin/cat" \; select-pane -t mouse:0.0
    : >"$TMUX_TMPDIR/keys"
    launch 23 NMUX_SELFTEST_KEYS="$TMUX_TMPDIR/keys" NMUX_SELFTEST_CELLS="42,0 47,0"
    check "the app attaches" within 10 isAttached
    within 10 logged "probe hold"
    check "the left pane starts active" is 0 active23
    act23 click left 60,5 0
    check "a click logs its SGR press and release" pressReleased23
    check "and tmux makes the right pane active" within 3 is 1 active23
    act23 wheel 1 0 1 0
    check "one notch up logs three wheel-up reports at the pointer" \
        within 3 is 3 grep -cx "selftest: mouse press four 60,5 -> 1b5b3c36343b36313b364d" "$LOG"
    check "and puts the pane in copy mode" within 3 is 1 $T display -p -t mouse:0.1 "#{pane_in_mode}"
    $T send -t mouse:0.1 -X cancel
    # A precise delta counts twice against the cell in pixels, so 5 cells take half as many points, rounded up.
    h=$(sed -n "s/^selftest: cell [0-9]*x\([0-9]*\) baseline .*/\1/p" "$LOG")
    act23 wheel -1 1 $(((5 * h + 1) / 2)) 0
    check "a precise run of deltas summing to five cell heights logs five wheel-down reports" fiveDown23
    $T set -t mouse mouse off
    sleep 1
    check "with mouse off, a click logs no report" quiet23 click left 10,5 0
    $T set -t mouse mouse on
    sleep 1
    check "a Shift+click logs no report" quiet23 click left 10,5 20002
    check "a middle click logs its press" clicked23 middle 1b5b3c313b31313b364d
    check "a right click logs its press" clicked23 right 1b5b3c323b31313b364d
    # tmux's mouse asks for button motion, not any motion.
    check "plain motion logs no report" quiet23 move 30,5 0
    check "the pointer is an I-beam over the terminal" is ibeam pointer23
    act23 move 42,0 100008
    check "held Cmd underlines the OSC 8 link under the pointer" within 3 underlined23
    check "and leaves the plain text after it as it is" is none field 47,0 deco
    check "and shows the pointing hand" is hand pointer23
    check "Cmd+click on the OSC 8 link opens its target" opens23 42,0 https://example.com/x
    check "and sends tmux nothing" not grep -q "^selftest: mouse .* 42,0 " "$LOG"
    check "Cmd+click on plain text does nothing" quiet23 click left 47,0 100008
    check "Cmd+click on a printed URL opens it" opens23 50,1 https://example.org/y
    $T kill-session -t mouse
    check "killing the Session ends the app" ended
}

lines24() { grep -c "^selftest: \(selection\|copy\|pasteboard\|shortcut\|mouse\|key\) " "$LOG"; }
# act24 <line>...: writes the lines at once and waits for a line they log.
act24() { n=$(lines24); printf '%s\n' "$@" >>"$TMUX_TMPDIR/keys"; within 3 over "$n" lines24; }
last() { grep "^selftest: $1 " "$LOG" | tail -1 | sed "s/^selftest: $1 //"; }
copies() { grep -c "^selftest: copy " "$LOG"; }
earlier24() { [ "$(last pasteboard)" = 6561726c696572 ] && [ "$(copies)" -eq 0 ]; }
# copied24 <hex>: Cmd+C copies that text.
copied24() { act24 "8 100008 63" && within 3 is "$1" last copy; }
swapped24() { [ "$(field 0,0 bg) $(field 0,0 fg)" = "$(field 0,1 fg) $(field 0,1 bg)" ]; }
selectionStart() { last selection | cut -d - -f 1; }
# selects24 <line> <selection>: the line leaves that selection.
selects24() { act24 "$1" && within 3 is "$2" last selection; }

# Run 24: the selection. tmux's mouse is on. A `drag <col>,<row> <col>,<row> <flags>` line presses near the first
# cell's left edge, drags to near the second's right edge and lets go; clicks in one poll of the keys file repeat
# into a double or a triple click. The view copies to the self-test's own pasteboard: `pasteboard <hex>` writes it,
# `pasteboard` logs it, and each copy logs its text. The theme has no selection colours, so a selected cell swaps the
# default colours, and Cmd+A selects from the first cell to the last with text, as Ghostty's select all.
run24() {
    $T new-session -d -s sel "/bin/stty -echo -icanon; /usr/bin/printf 'alpha beta\ngamma\n'; exec /bin/cat" \
        \; set -t sel status off \; set -t sel mouse on
    : >"$TMUX_TMPDIR/keys"
    launch 24 NMUX_SELFTEST_KEYS="$TMUX_TMPDIR/keys" NMUX_SELFTEST_CELLS="0,0 0,1"
    check "the app attaches" within 10 isAttached
    within 10 logged "probe hold"
    n=$(settles); settled $n
    act24 "pasteboard 6561726c696572" "8 100008 63" && act24 pasteboard
    check "Cmd+C with no selection leaves the pasteboard's earlier string" earlier24
    act24 "drag 0,0 4,0 20002"
    check "a Shift+drag across alpha selects it" within 3 is 0,0-4,0 last selection
    check "and sends tmux no mouse report" not grep -q "^selftest: mouse " "$LOG"
    check "and copies nothing yet" is 0 copies
    check "Cmd+C puts alpha on the pasteboard" copied24 616c706861
    check "a selected cell draws the default foreground under the default background" within 3 swapped24
    check "the readback finds the selected cell's background" \
        within 5 logged "readback bg ok ink 0,0 ok cursor ok selected ok"
    sleep 1
    act24 "click left 7,0 20002" "click left 7,0 20002"
    check "a Shift+double-click on beta selects the word" within 3 is 6,0-9,0 last selection
    check "and Cmd+C copies beta" copied24 62657461
    sleep 1
    act24 "click left 2,0 20002" "click left 2,0 20002" "click left 2,0 20002"
    check "a Shift+triple-click selects the line" within 3 is 0,0 selectionStart
    check "and Cmd+C copies alpha beta" copied24 616c7068612062657461
    sleep 1
    check "a single Shift+click clears the selection" selects24 "click left 2,0 20002" none
    act24 "drag 0,1 4,1 20002"
    within 3 is 0,1-4,1 last selection
    check "a click without Shift clears it too" selects24 "click left 2,1 0" none
    check "Cmd+A selects the whole screen" selects24 "0 100008 61" 0,0-4,1
    check "a key typed below the selection drops it" selects24 "7 0 78" none
    $T kill-session -t sel
    check "killing the Session ends the app" ended
}

dragCopies25() { act24 "drag 0,1 4,1 20002" && within 3 is 67616d6d61 last copy; }
selectionColours25() { [ "$(field 0,1 bg) $(field 0,1 fg)" = "ff0000 00ff00" ]; }
loneSelected25() { [ "$(last selection)" = 1,2-1,2 ] && [ "$(field 1,2 glyph)" = "$lone" ]; }
dashAlone25() { act24 "drag 1,2 1,2 20002" && within 3 loneSelected25; }

# Run 25: under a theme's selection colours and copy-on-select true, in the bundled Maple Mono, whose `->` is one
# ligature. Releasing a Shift+drag copies, and selecting only the `-` of `x->` breaks the ligature.
run25() {
    $T new-session -d -s sel "/bin/stty -echo -icanon; /usr/bin/printf 'alpha beta\ngamma\nx->\n-\n'; exec /bin/cat" \
        \; set -t sel status off \; set -t sel mouse on
    : >"$TMUX_TMPDIR/keys"
    launch 25 NMUX_SELFTEST_KEYS="$TMUX_TMPDIR/keys" NMUX_SELFTEST_CELLS="0,1 1,2 2,2 0,3" \
        NMUX_SELFTEST_FONT=MapleMono-Regular.ttf \
        NMUX_SELFTEST_COPY_ON_SELECT=true NMUX_SELFTEST_SELECTION_COLORS="ff0000 00ff00"
    check "the app attaches" within 10 isAttached
    within 10 logged "probe hold"
    n=$(settles); settled $n
    lone=$(field 0,3 glyph) joined=$(field 1,2 glyph)
    check "-> draws its - unlike a lone - before any selection" [ "$joined" != "$lone" ]
    check "releasing a Shift+drag across gamma copies it without Cmd+C" dragCopies25
    check "a selected cell draws in the theme's selection colours" within 3 selectionColours25
    check "the readback finds the selection background" \
        within 5 logged "readback bg ok ink 0,1 ok cursor ok selected ok"
    check "selecting only the - of x-> draws it as a lone -" dashAlone25
    check "and > draws a glyph of its own" is 1 field 2,2 glyphs
    $T kill-session -t sel
    check "killing the Session ends the app" ended
}

lines26() { grep -c "^selftest: \(paste\|card\|press\|pasteboard\|shortcut\|osc52\) " "$LOG"; }
# act26 <line>...: writes the lines at once and waits for a line they log.
act26() { n=$(lines26); printf '%s\n' "$@" >>"$TMUX_TMPDIR/keys"; within 3 over "$n" lines26; }
bytes() { xxd -p "$TMUX_TMPDIR/$1" | tr -d '\n'; }
cards() { grep -c "^selftest: card $1\$" "$LOG"; }
noCard26() { within 3 is 6f6e65 bytes pasted && [ "$(cards paste)" -eq 0 ]; }
stillOne26() { sleep 0.5; [ "$(bytes pasted)" = 6f6e65 ]; }
pastedBoth26() { within 3 logged "press paste" && within 3 is 6f6e65610a62 bytes pasted; }
bracketed26() { within 3 logged "paste 610a62 bracketed=yes" && [ "$(cards paste)" -eq 2 ]; }

# Run 26: paste. The pane's `tee` keeps the bytes it gets. Cmd+V pastes the self-test's pasteboard through
# libghostty-vt: a plain line goes straight in; two lines without bracketed paste show the paste card first, where
# Escape sends nothing and Return sends both; once the pane turns bracketed paste on, the same two lines go in wrapped,
# with no card, and go there even when Cmd+2 shows another Session before tmux says the pane is bracketed.
run26() {
    $T new-session -d -s paste "/bin/stty raw -echo; exec /usr/bin/tee $TMUX_TMPDIR/pasted" \; set -t paste status off
    : >"$TMUX_TMPDIR/keys"
    launch 26 NMUX_SELFTEST_KEYS="$TMUX_TMPDIR/keys"
    check "the app attaches" within 10 isAttached
    within 10 logged "probe hold"
    act26 "pasteboard 6f6e65" "9 100008 76"
    check "Cmd+V pastes one" within 3 logged "paste 6f6e65 bracketed=no"
    check "and the pane receives it, with no card" noCard26
    act26 "pasteboard 610a62" "9 100008 76"
    check "two lines without bracketed paste show the paste card" within 3 is 1 cards paste
    check "and send nothing yet" stillOne26
    act26 "53 0 1b"
    check "Escape on the card cancels" within 3 logged "press cancel"
    check "and sends nothing" stillOne26
    act26 "9 100008 76"
    within 3 is 2 cards paste
    act26 "36 0 0d"
    # tmux unwraps the bracketed paste its client sends for a pane that never asked for brackets, newline and all.
    check "Return on the card pastes both lines" pastedBoth26
    $T respawn-pane -k -t paste \
        "/usr/bin/printf '\033[?2004h'; /bin/stty raw -echo; exec /usr/bin/tee $TMUX_TMPDIR/bracketed"
    sleep 1
    act26 "9 100008 76"
    check "after the pane turns bracketed paste on, the two lines paste with no card" bracketed26
    check "wrapped in ESC [200~ and ESC [201~" within 3 is 1b5b3230307e610a621b5b3230317e bytes bracketed
    $T new-session -d -s other "/bin/stty raw -echo; exec /usr/bin/tee $TMUX_TMPDIR/other" \; set -t other status off
    within 5 logged 'sessions $0:paste $1:other'
    act26 "9 100008 76" "goto session-2"
    check "a switch of Session before tmux answers leaves the paste in the Session of Cmd+V" \
        within 3 is 1b5b3230307e610a621b5b3230317e1b5b3230307e610a621b5b3230317e bytes bracketed
    check "and nothing in the Session shown" not test -s "$TMUX_TMPDIR/other"
    $T kill-session -t other
    $T kill-session -t paste
    check "killing the Session ends the app" ended
}

# wrote27 <hex>: an OSC 52 write of that text reached the pasteboard.
wrote27() { within 3 logged "osc52 write $1" && act26 pasteboard && [ "$(last pasteboard)" = "$1" ]; }
denied27() { within 3 logged "press deny" && within 3 logged "osc52 read none"; }
noReply27() { sleep 0.5; [ -z "$(bytes read)" ]; }
kept27() {
    within 3 logged "press deny" && act26 pasteboard && [ "$(last pasteboard)" = 6869 ] \
        && ! grep -q "^selftest: osc52 write" "$LOG"
}
allowed27() { within 3 logged "osc52 read 6869" && ! grep -q "^selftest: card read" "$LOG"; }
answered27() { bytes allowed | grep -q 61476b3d; }

# Run 27: OSC 52, with tmux's set-clipboard on and get-clipboard request. A copy in tmux's copy mode and a pane's own
# OSC 52 write reach the self-test's pasteboard. A pane's read shows the read card, where Return denies and the pane
# gets no reply. Under clipboard-read allow, a read gets the pasteboard's text; under clipboard-write ask, a write shows
# the write card, and Escape leaves the pasteboard as it was.
run27() {
    $T new-session -d -s osc "/usr/bin/printf 'hi\n'; exec /bin/cat" \
        \; set -t osc status off \; set -s set-clipboard on \; set -s get-clipboard request
    : >"$TMUX_TMPDIR/keys"
    launch 27 NMUX_SELFTEST_KEYS="$TMUX_TMPDIR/keys"
    check "the app attaches" within 10 isAttached
    within 10 logged "probe hold"
    # tmux drops a clipboard write while the client waits for a redraw, so the copy waits for copy mode's own.
    $T copy-mode -t osc \; send -t osc -X history-top \; send -t osc -X start-of-line \
        \; send -t osc -X begin-selection \
        \; send -t osc -X end-of-line
    sleep 0.5
    $T send -t osc -X copy-selection-and-cancel
    check "a copy in tmux's copy mode reaches the pasteboard" wrote27 6869
    # The pane prints before it reads, so each respawn writes its own file.
    $T respawn-pane -k -t osc "/usr/bin/printf '\033]52;c;aG8=\007'; exec /bin/cat"
    check "a pane's OSC 52 write reaches the pasteboard" wrote27 686f
    $T respawn-pane -k -t osc \
        "/bin/stty raw -echo; /usr/bin/printf '\033]52;c;?\007'; exec /usr/bin/tee $TMUX_TMPDIR/read"
    check "a pane's read shows the read card" within 3 logged "card read"
    act26 "36 0 0d"
    check "Return on the read card denies" denied27
    check "and the pane gets no reply" noReply27
    $T kill-session -t osc
    check "killing the Session ends the app" ended
    $T new-session -d -s osc "/bin/cat" \; set -t osc status off \
        \; set -s set-clipboard on \; set -s get-clipboard request
    : >"$TMUX_TMPDIR/keys"
    launch 27-allow NMUX_SELFTEST_KEYS="$TMUX_TMPDIR/keys" \
        NMUX_SELFTEST_CLIPBOARD_READ=allow NMUX_SELFTEST_CLIPBOARD_WRITE=ask
    check "the app attaches" within 10 isAttached
    within 10 logged "probe hold"
    act26 "pasteboard 6869" pasteboard
    $T respawn-pane -k -t osc "/usr/bin/printf '\033]52;c;aG8=\007'; exec /bin/cat"
    check "under clipboard-write ask, a write shows the write card" within 3 logged "card write"
    act26 "53 0 1b"
    check "and Escape leaves the pasteboard as it was" kept27
    # tmux keeps the reply as a buffer and writes it back to the client, which shows the write card again; the seam
    # stops there.
    $T respawn-pane -k -t osc \
        "/bin/stty raw -echo; /usr/bin/printf '\033]52;c;?\007'; exec /usr/bin/tee $TMUX_TMPDIR/allowed"
    check "under clipboard-read allow, a read gets the pasteboard's text with no read card" allowed27
    check "and the pane receives it in OSC 52" within 3 answered27
    $T kill-session -t osc
    check "killing the Session ends the app" ended
}
