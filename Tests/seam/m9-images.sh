# Milestone 9, kitty images: run 42.

# The 2×1 PNG of `redBlue` in Tests/nmuxTests/Fixtures.swift: red ff0000 left, blue 0000ff right.
png42="iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAIAAAB7QOjdAAAADUlEQVR4nGP4zwAE/wEHAAH/4iOeWQAAAABJRU5ErkJggg=="
# out42 <printf format>: the bytes written to the pane's terminal, as if its program printed them.
out42() { /usr/bin/printf "$1" >"$($T display -p -t img '#{pane_tty}')"; }
# kitty42 <control data>: a kitty command wrapped in tmux's passthrough, every escape inside doubled.
kitty42() { out42 "\033Ptmux;\033\033_G$1\033\033\\\\\033\\\\"; }
# pix42 <x,y>: the colour the last settled frame read at the cell's centre.
pix42() { grep "^selftest: pixel $1 " "$LOG" | tail -1 | cut -d' ' -f4; }
# bg42 <x,y>...: each cell reads as the far cell 40,12, which nothing covers.
bg42() {
    _bg=$(pix42 40,12); [ -n "$_bg" ] || return 1
    for _c in "$@"; do [ "$(pix42 "$_c")" = "$_bg" ] || return 1; done
}
shows42() { [ "$(pix42 "3,$1")" = ff0000 ] && [ "$(pix42 "4,$1")" = 0000ff ]; }
# row42: the screen row, from 0, that the marker printed beside the image is on now.
row42() { grep -n "^MK" "$TMUX_TMPDIR/screen42" | head -1 | cut -d: -f1 | awk '{ print $1 - 1 }'; }
scrolled42() { _r=$(row42); [ -n "$_r" ] && [ "$_r" -lt 2 ] && shows42 "$_r"; }

# Run 42: an image a program sends through tmux's passthrough shows in nmux. Two cells at 3,2 and 4,2 read red and blue,
# the cells around them the background. Output that scrolls the pane moves the image up with the text beside it, and
# the cells it left read the background; the row it reached is measured from where the text went, since tmux scrolls
# a pane inside a scroll region while its status line is on. Deleting it leaves the background. `q=2` keeps the
# terminal's reply out of the pane and `C=1` keeps the cursor where tmux believes it is.
run42() {
    $T new-session -d -s img "/bin/stty -echo -icanon; exec /bin/cat"
    launch 42 NMUX_SELFTEST_SCREEN="$TMUX_TMPDIR/screen42" \
        NMUX_SELFTEST_CELLS="3,2 4,2 2,2 5,2 3,1 4,1 3,3 3,0 4,0 40,12"
    check "the app attaches" within 10 isAttached
    within 10 logged "probe hold"
    out42 '\033[3;1HMK\033[3;4H'
    kitty42 "a=T,f=100,c=2,r=1,q=2,C=1;$png42"
    check "the image's cells read red and blue" within 10 shows42 2
    check "the cells around it read the background" within 5 bg42 2,2 5,2 3,1 4,1 3,3
    out42 '\033[999;1H\n\n'
    check "output that scrolls the pane moves the image up with its text" within 10 scrolled42
    check "and the cells it left read the background" within 5 bg42 3,2 4,2
    row42=$(row42)
    kitty42 "a=d,q=2"
    check "a deleted image leaves the background" within 10 bg42 "3,$row42" "4,$row42"
    check "the app still runs" alive
    kill "$PID"
    check "the app quits on SIGTERM" ended
}
