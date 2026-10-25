# Milestone 2, the VT host and the first frames: runs 11 to 13.

reply() { sed -n "s/^selftest: reply //p" "$LOG" | sed -n "$1p"; }
replyMatches() { reply "$1" | grep -qE "$2"; }
releasedAfterProbe() { sed -n '/^selftest: probe hold$/,$p' "$LOG" | grep -qxF "selftest: hold released"; }
paneShows() { $T capture-pane -p -t "$1" | grep -qF "$2"; }
backgroundReplied() { [ -n "$rgb" ] && within 3 paneShows "$(attached)" "$rgb"; }

# Run 11: the VT host parses what the client writes, answers queries through the pty, keeps the colours of each
# appearance and ends a hold no one ends. The pane runs the author's login shell, so it prints by full path.
run11() {
    launch 11 NMUX_SELFTEST_SCREEN="$TMUX_TMPDIR/screen"
    check "the app attaches" within 10 isAttached
    check "the client's output is parsed" within 10 grep -q "^selftest: vt [1-9][0-9]* bytes parsed\$" "$LOG"
    # The probe's hold starts as its line is logged, so the 1.5 s count from the moment the seam sees that line.
    within 10 logged "probe hold"
    check "a hold no one ends is released within 1.5 s" soon 15 releasedAfterProbe
    check "primary device attributes get ESC [ ? ... c" within 3 replyMatches 1 "^1b5b3f(3[0-9]|3b)+63\$"
    check "a cursor position report gets ESC [ row ; col R" replyMatches 2 "^1b5b(3[0-9])+3b(3[0-9])+52$"
    check "the default background is #000000 in dark mode" logged "background dark #000000"
    check "and #ffffff in light mode" logged "background light #ffffff"
    $T send-keys -t "$(attached)" "/bin/echo hello" Enter
    check "what the pane prints reaches the terminal's screen" within 5 grep -qx hello "$TMUX_TMPDIR/screen"
    # The reply comes back as the shell's input: `rgb:` and each channel twice, from the background the app logged.
    rgb=$(sed -n "s/^selftest: background system #\(..\)\(..\)\(..\)$/rgb:\1\1\/\2\2\/\3\3/p" "$LOG")
    $T send-keys -t "$(attached)" "printf '\\033]11;?\\007'" Enter
    check "a pane asking for the background gets it back" backgroundReplied
    $T kill-session -t "$(attached)"
    check "killing the Session ends the app" ended
    check "and exits with 0" [ "$status" -eq 0 ]
}

# Each settle of the frames logs the named cells and the cursor; a step waits for the next settle after it.
settles() { grep -c "^selftest: cursor " "$LOG"; }
settled() { within 5 over "$1" settles; }
cell() { grep "^selftest: cell $1 " "$LOG" | tail -1 | sed "s/^selftest: cell $1 //"; }
field() { cell "$1" | tr ' ' '\n' | sed -n "s/^$2=//p"; }
cursor() { grep "^selftest: cursor " "$LOG" | tail -1 | sed "s/^selftest: cursor //"; }
framesLogged() { grep -c "^selftest: frames " "$LOG"; }
# frames: asks for the frames presented and prints the count, or nothing when the app gives none within 1 s.
frames() {
    n=$(framesLogged); kill -USR1 "$PID"
    soon 10 over "$n" framesLogged && sed -n "s/^selftest: frames //p" "$LOG" | tail -1
}
gap() { sed -n "s/^selftest: frame gap //p" "$LOG" | tail -1; }
# plain <cell>...: each cell holds a glyph in the default colours.
plain() {
    for c; do
        [ "$(field $c face)" != none ] && [ "$(field $c glyph)" != 0 ] && [ "$(field $c fg)" = "$fg" ] \
            && [ "$(field $c bg)" = "$bg" ] || return 1
    done
}
inverse12() { [ "$(field 0,3 fg)" = "$bg" ] && [ "$(field 0,3 bg)" = "$fg" ]; }
otherFace12() {
    f=$(field 1,4 face); [ "$f" != none ] && [ "$f" != "$(sed -n "s/^selftest: face U+0041 //p" "$LOG")" ]
}
bar12() {
    settled $n && [ "$(cursor)" = "0,5 bar $fg" ] && [ "$(grep "^selftest: cell " "$LOG" | tail -7)" = "$before" ]
}
quiet12() { [ -n "$a" ] && [ "$a" = "$b" ]; }
hidden12() { settled $n && [ "$(cursor)" = none ]; }
flooded12() { [ "$flood" = ok ] && [ -e "$TMUX_TMPDIR/flooded" ]; }

# Run 12: the renderer draws the cells the pane prints, in their colours, and the cursor the program asks for; a quiet
# prompt draws no frames, a flood keeps them landing, and one frame read back holds the pixels the cells say. The
# pane starts at once with its own command, so it neither echoes what the seam types nor runs the login shell.
run12() {
    pane12="/bin/stty -echo -icanon; /usr/bin/printf 'AB\n\033[31mR\033[0m\n\033[38;2;1;2;3mT\033[0m\n\033[7mI\033[0m"
    pane12="$pane12\nł中\n'; exec /bin/cat"
    $T new-session -d -s draw "$pane12"
    launch 12 NMUX_SELFTEST_CELLS="0,0 1,0 0,1 0,2 0,3 0,4 1,4"
    check "the app attaches" within 10 isAttached
    # The probe flips the appearance, so the cells count from the first settle after it.
    within 10 logged "probe hold"
    n=$(settles); settled $n
    bg=$(sed -n "s/^selftest: background system #//p" "$LOG")
    fg=$([ "$bg" = ffffff ] && echo 000000 || echo ffffff)
    check "A and B are drawn as glyphs in the default colours" plain 0,0 1,0
    check "red is drawn in Basic's #990000" is 990000 field 0,1 fg
    check "truecolor is drawn as asked" is 010203 field 0,2 fg
    check "inverse swaps the default colours" inverse12
    check "ł is drawn as a glyph" not is 0 field 0,4 glyph
    check "中 is drawn from a face other than SF Mono's" otherFace12
    check "the cursor is a block where the program waits" is "0,5 block $fg" cursor
    check "the readback finds the background, A's ink and the cursor" \
        within 5 logged "readback bg ok ink 0,0 ok cursor ok"
    before=$(grep "^selftest: cell " "$LOG" | tail -7)
    n=$(settles); $T send-keys -t draw -l "$(printf '\033[6 q')"
    check "a bar cursor is drawn without any cell changing" bar12
    a=$(frames); sleep 5; b=$(frames)
    check "a quiet prompt draws no frame in 5 s" quiet12
    n=$(settles); $T send-keys -t draw -l "$(printf '\033[?25l')"
    check "a hidden cursor is not drawn" hidden12
    # 50 MB of text: every half second while the pane prints, the app answers within 1 s with the longest gap between
    # its presented frames since the last answer, which must stay within 1 s.
    yes 'the quick brown fox jumps over the lazy dog, 0123456789 and once more' | head -c 52428800 >"$TMUX_TMPDIR/big"
    frames >/dev/null
    $T respawn-pane -k -t draw "/bin/cat $TMUX_TMPDIR/big; : >$TMUX_TMPDIR/flooded; exec /bin/cat"
    flood=ok i=0
    while [ ! -e "$TMUX_TMPDIR/flooded" ] && [ $i -lt 240 ]; do
        sleep 0.5; i=$((i + 1))
        if [ -z "$(frames)" ]; then flood="no answer within 1 s"; break; fi
        if [ ! -e "$TMUX_TMPDIR/flooded" ] && [ "$(gap)" -gt 1000 ]; then flood="a gap of $(gap) ms"; break; fi
    done
    echo "     flood: $i polls, $flood"
    check "a flood keeps frames landing and the app answering" flooded12
    $T kill-session -t draw
    check "killing the Session ends the app" ended
    check "and exits with 0" [ "$status" -eq 0 ]
}

oks() { grep -c "^selftest: readback bg ok ink 0,0 ok cursor ok$" "$LOG"; }
tmuxWindow() { $T display -p -t size "#{window_width} #{window_height}"; }
tmuxClient() { plains "#{client_width} #{client_height}"; }
contentLines() { grep -c "^selftest: content " "$LOG"; }
step() {
    n=$(contentLines); kill -USR2 "$PID"; within 3 over "$n" contentLines
    sed -n "s/^selftest: content //p" "$LOG" | tail -1 | tr x ' '
}
# part <content line> <fields>: the fields named, of `W H grid C R cell w h scale s`.
part() { echo "$1" | cut -d " " -f "$2"; }
whole() { part "$1" 1,2,4,5,7,8,10 | holds; }
# scaled <content line> <scale>: the app logged the cell it measured at that scale, and the line is at it.
scaled() { logged "scale $2 cell $(part "$1" 7)x$(part "$1" 8)" && [ "$(part "$1" 10)" = "$2" ]; }
halfCell() { echo "$atOne $atTwo" | awk '{ exit !(($7 - $17 / 2) ^ 2 <= 1 && ($8 - $18 / 2) ^ 2 <= 1) }'; }

# Run 13: the grid follows the window. Each SIGUSR2 takes the self-test's next resize step and logs `content W H grid
# C R cell w h scale s` 0.5 s later: three columns and two rows fewer, half a cell wider than that grid, scale 1, scale
# 2.
run13() {
    $T new-session -d -s size "/bin/stty -echo -icanon; /usr/bin/printf 'AB\n'; exec /bin/cat"
    launch 13 NMUX_SELFTEST_CELLS="0,0"
    check "the app attaches" within 10 isAttached
    within 10 over 0 oks
    before=$(tmuxWindow)
    shrunk=$(step)
    check "tmux's window loses three columns and two rows" \
        within 1 is "$(($(part "$before" 1) - 3)) $(($(part "$before" 2) - 2))" tmuxWindow
    check "the app logs the grid it resized to" logged "resize $(part "$shrunk" 4)x$(part "$shrunk" 5)"
    widened=$(step)
    check "half a cell wider keeps the grid" is "$(part "$shrunk" 4-5)" part "$widened" 4-5
    check "and the window ends on whole cells" whole "$widened"
    n=$(oks); atOne=$(step)
    check "scale 1 measures the cell again" scaled "$atOne" 1
    check "the window holds whole cells of it" whole "$atOne"
    check "tmux follows its grid" within 1 is "$(part "$atOne" 4-5)" tmuxClient
    check "the readback still finds the background, A's ink and the cursor" within 5 over "$n" oks
    n=$(oks); atTwo=$(step)
    check "scale 2 measures the cell again" scaled "$atTwo" 2
    check "the cell at 1 is half the cell at 2, within a pixel" halfCell
    check "the window holds whole cells of it" whole "$atTwo"
    check "tmux follows its grid" within 1 is "$(part "$atTwo" 4-5)" tmuxClient
    check "the readback still finds the background, A's ink and the cursor" within 5 over "$n" oks
    check "no frame was late" not logged "late frame"
    $T kill-session -t size
    check "killing the Session ends the app" ended
    check "and exits with 0" [ "$status" -eq 0 ]
}
