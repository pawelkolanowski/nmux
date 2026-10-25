# Milestone 3, the renderer: runs 14 to 18.

faced() { [ "$(field $1 face)" != none ] && [ "$(field $1 style)" = $2 ] && [ "$(field $1 synthetic)" = no ]; }
ownFaces14() { faced 0,0 bold && faced 1,0 bolditalic && faced 2,0 italic; }
invisible14() { [ "$(field 0,2 face)" = none ] && [ "$(field 0,2 bg)" = 0000ff ] && [ "$(field 0,2 deco)" = none ]; }
underlines14() {
    [ "$(field 1,3 deco) $(field 2,3 deco) $(field 3,3 deco) $(field 4,3 deco)" \
        = "underline-double:#$fg underline-dotted:#$fg underline-dashed:#$fg underline:#$fg" ]
}
struck14() {
    [ "$(field 0,4 deco)" = "strike:#$fg" ] && [ "$(field 1,4 deco)" = "overline:#$fg,strike:#$fg" ] \
        && [ "$(field 3,4 deco)" = none ]
}
wide14() { [ "$(field 0,5 deco)" = "underline:#$fg" ] && [ "$(field 1,5 deco)" = none ]; }

# Run 14: each cell draws in its style's face with its decorations: bold, bold italic and italic; faint; invisible on
# blue; a curly underline in SGR 58's red, then double, dotted, dashed and straight in the text's colour;
# strikethrough, then strikethrough and overline, then a plain P; an underlined 中, one decoration over both its cells.
# The readback finds ink in the curly underline's rows and none in B's.
run14() {
    pane14="/bin/stty -echo -icanon; /usr/bin/printf '\033[1mB\033[3mI\033[22mi\033[0m\n\033[2mF\033[0m\n"
    pane14="$pane14\033[8;48;2;0;0;255mH\033[0m\n\033[4:3;58;2;255;0;0mU\033[59;4:2mD\033[4:4mO\033[4:5mA\033[4mS"
    pane14="$pane14\033[0m\n\033[9mS\033[53mO\033[0m P\n\033[4m中\033[0m\n'; exec /bin/cat"
    $T new-session -d -s styles "$pane14"
    launch 14 NMUX_SELFTEST_CELLS="0,0 1,0 2,0 0,1 0,2 0,3 1,3 2,3 3,3 4,3 0,4 1,4 3,4 0,5 1,5"
    check "the app attaches" within 10 isAttached
    within 10 logged "probe hold"
    n=$(settles); settled $n
    bg=$(sed -n "s/^selftest: background system #//p" "$LOG")
    fg=$([ "$bg" = ffffff ] && echo 000000 || echo ffffff)
    check "bold, bold italic and italic draw in SF Mono's own faces" ownFaces14
    check "faint text draws its foreground at half opacity" is "${fg}80" field 0,1 fg
    check "invisible text draws its background and no glyph" invisible14
    check "a curly underline takes SGR 58's red" is "underline-curly:#ff0000" field 0,3 deco
    check "double, dotted, dashed and straight underlines take the text's colour" underlines14
    check "strikethrough, then overline with strikethrough, are drawn" struck14
    check "an underlined wide cell carries one underline, over its head" wide14
    check "the readback finds the underline's ink and none under a plain cell" \
        within 5 logged "readback bg ok ink 0,0 ok cursor ok underline 0,3 ok plain 0,0 ok"
    $T kill-session -t styles
    check "killing the Session ends the app" ended
    check "and exits with 0" [ "$status" -eq 0 ]
}

wide15() { [ "$(field 0,0 span) $(field 0,0 cluster) $(field 0,0 glyphs)" = "2 4e2d 1" ]; }
spacer15() { [ "$(field 1,0 face) $(field 1,0 glyphs)" = "none 0" ]; }
third15() { [ "$(field 2,0 cluster) $(field 2,0 glyphs)" = "61 1" ]; }
combined15() { [ "$(field 0,1 cluster) $(field 0,1 glyphs)" = "65,301 1" ]; }
ligature15() { [ "$(field 0,2 face)" = Maple ] && [ "$(field 0,2 glyphs) $(field 1,2 glyphs)" = "0 1" ]; }
broken15() {
    settled $n && [ "$(cursor | cut -d " " -f 1)" = 1,4 ] && [ "$(field 0,4 glyph)" = "$lone" ] \
        && [ "$(field 1,4 glyph)" != "${joined#* }" ]
}
shaped() { grep "^selftest: shaped " "$LOG" | tail -1 | sed "s/^selftest: shaped //"; }
oneRow15() { settled $n && [ "$(shaped)" = 1 ]; }

# Run 15: each row is shaped by runs in the bundled Maple Mono. 中 spans two cells and its spacer draws nothing; e and a
# combining acute draw as one glyph on one cell; `!=` draws one glyph over two cells; `->` draws its `-` unlike a lone
# `-` until the cursor sits on `>`. After a full screen, one typed letter shapes one row; the status line is off, as
# tmux renames the window in it when the pane prints.
run15() {
    $T new-session -d -s shape \
        "/bin/stty -echo -icanon; /usr/bin/printf '\344\270\255a\ne\314\201\n!=\n-\n->'; exec /bin/cat" \
        \; set -t shape status off
    launch 15 NMUX_SELFTEST_FONT=MapleMono-Regular.ttf NMUX_SELFTEST_CELLS="0,0 1,0 2,0 0,1 0,2 1,2 0,3 0,4 1,4"
    check "the app attaches" within 10 isAttached
    within 10 logged "probe hold"
    n=$(settles); settled $n
    check "中 spans two cells with its own cluster" wide15
    check "its spacer draws nothing" spacer15
    check "a follows in the third cell" third15
    check "e and a combining acute draw as one glyph on one cell" combined15
    check "!= draws one glyph over its two cells" ligature15
    lone=$(field 0,3 glyph) joined="$(field 0,4 glyph) $(field 1,4 glyph)"
    check "-> shapes its - unlike a lone -" [ "${joined% *}" != "$lone" ]
    n=$(settles); $T send-keys -t shape -l "$(printf '\033[D')"
    check "the cursor on > breaks -> into each cell's own glyph" broken15
    n=$(settles); $T respawn-pane -k -t shape "/bin/stty -echo -icanon; /usr/bin/seq 1 500; exec /bin/cat"
    settled $n; sleep 1
    n=$(settles); $T send-keys -t shape -l x
    check "one letter typed after a full screen shapes one row" oneRow15
    $T kill-session -t shape
    check "killing the Session ends the app" ended
    check "and exits with 0" [ "$status" -eq 0 ]
}

# emoji <cell>: the cell draws from Apple Color Emoji, whose name `field` would cut at its first space.
emoji() { cell "$1" | grep -q "^face=Apple Color Emoji glyph="; }
smiley16() { emoji 0,0 && [ "$(field 0,0 atlas) $(field 0,0 span) $(field 0,0 glyphs)" = "color 2 1" ]; }
hearts16() { [ "$(field 0,1 atlas) $(field 0,2 atlas)" = "color text" ] && [ "$(field 0,2 glyphs)" = 1 ]; }
# drawnWhole <cell> <cluster>: the cell holds the whole cluster and draws it as one glyph from Apple Color Emoji.
drawnWhole() { emoji $1 && [ "$(field $1 cluster) $(field $1 atlas) $(field $1 glyphs)" = "$2 color 1" ]; }
flagFamily16() { drawnWhole 0,3 1f1f5,1f1f1 && drawnWhole 0,4 1f468,200d,1f469,200d,1f467; }
toneKeycap16() { drawnWhole 0,5 1f44d,1f3fd && drawnWhole 0,6 31,fe0f,20e3; }

# Run 16: colour emoji. 🙂 draws from the colour atlas over two cells in Apple Color Emoji, and the readback finds a
# colour no blend of the text's gives; a heart with VS16 draws in colour, one with VS15 as text; a flag, a joined
# family, a skin tone and a keycap each draw as one colour glyph.
run16() {
    pane16="/bin/stty -echo -icanon; /usr/bin/printf '\360\237\231\202\n\342\235\244\357\270\217\n\342\235\244\357\270"
    pane16="$pane16\216\n\360\237\207\265\360\237\207\261\n\360\237\221\250\342\200\215\360\237\221\251\342\200\215\360"
    pane16="$pane16\237\221\247\n\360\237\221\215\360\237\217\275\n\061\357\270\217\342\203\243'; exec /bin/cat"
    $T new-session -d -s emoji "$pane16" \
        \; set -t emoji status off
    launch 16 NMUX_SELFTEST_CELLS="0,0 0,1 0,2 0,3 0,4 0,5 0,6"
    check "the app attaches" within 10 isAttached
    within 10 logged "probe hold"
    n=$(settles); settled $n
    check "🙂 draws from the colour atlas over two cells in Apple Color Emoji" smiley16
    check "a heart with VS16 draws in colour, one with VS15 as text" hearts16
    check "a flag and a joined family each draw as one colour glyph" flagFamily16
    check "a skin tone and a keycap each draw as one colour glyph" toneKeycap16
    check "the readback finds a colour in 🙂's cells that no blend of the text's colours gives" \
        within 5 logged "readback bg ok ink 0,0 ok cursor ok color ok"
    $T kill-session -t emoji
    check "killing the Session ends the app" ended
    check "and exits with 0" [ "$status" -eq 0 ]
}

sprite() { [ "$(field $1 face) $(field $1 glyph)" = "sprite $2" ]; }
border() { for y in $(seq 0 23); do sprite $b,$y U+2502 || return 1; done; }
borderDrawn17() { [ -n "$b" ] && border; }
blocks17() { sprite 0,0 U+2588 && sprite 1,0 U+28FF; }
unassigned17() { sprite 2,0 U+1FB93 && [ "$(field 2,0 glyphs)" = 0 ]; }

# Run 17: sprites. The border between two panes side by side draws from the sprite face down its whole column; █ and
# ⣿ draw from it too, though SF Mono has █, which takes its foreground as its background; unassigned U+1FB93 draws
# nothing and still logs its codepoint; the readback finds ⣿'s ink.
# The window keeps 80 x 24 whatever the client's size, so the border's column and height are known before the launch.
run17() {
    $T new-session -d -s sprites \
        "/bin/stty -echo -icanon; /usr/bin/printf '\342\226\210\342\243\277\360\237\256\223'; exec /bin/cat" \
        \; set -t sprites status off \; set -t sprites window-size manual \; resize-window -t sprites -x 80 -y 24 \
        \; split-window -h -t sprites "exec /bin/cat"
    b=$($T display -p -t sprites:0.0 '#{pane_width}')
    launch 17 NMUX_SELFTEST_CELLS="1,0 0,0 2,0 $(for y in $(seq 0 23); do printf '%s ' "$b,$y"; done)"
    check "the app attaches" within 10 isAttached
    within 10 logged "probe hold"
    n=$(settles); settled $n
    check "the border between the panes draws from the sprite face down its whole column" borderDrawn17
    check "█ and ⣿ draw from the sprite face" blocks17
    check "unassigned U+1FB93 draws nothing from the sprite face and still names itself" unassigned17
    check "█ takes its foreground as its background" is "$(field 0,0 fg)" field 0,0 bg
    check "the readback finds ⣿'s ink" within 5 logged "readback bg ok ink 1,0 ok cursor ok"
    $T kill-session -t sprites
    check "killing the Session ends the app" ended
    check "and exits with 0" [ "$status" -eq 0 ]
}

# icon <cell> <span>: the cell draws U+F015 as one glyph from Symbols Nerd Font, whose name `field` would cut at its
# first space, over <span> cells.
icon() {
    cell "$1" | grep -q "^face=Symbols Nerd Font glyph=" \
        && [ "$(field $1 cluster) $(field $1 glyphs) $(field $1 span)" = "f015 1 $2" ]
}

# Run 18: Nerd Font icons. U+F015 followed by a space draws from the bundled Symbols Nerd Font over two cells, followed
# by a letter over one; the readback finds the icon's ink.
run18() {
    $T new-session -d -s icons \
        "/bin/stty -echo -icanon; /usr/bin/printf '\357\200\225 x\n\357\200\225x'; exec /bin/cat" \
        \; set -t icons status off
    launch 18 NMUX_SELFTEST_CELLS="0,0 0,1"
    check "the app attaches" within 10 isAttached
    within 10 logged "probe hold"
    n=$(settles); settled $n
    check "an icon followed by a space draws from the bundled Symbols Nerd Font over two cells" icon 0,0 2
    check "an icon followed by a letter stays in one cell" icon 0,1 1
    check "the readback finds the icon's ink" within 5 logged "readback bg ok ink 0,0 ok cursor ok"
    $T kill-session -t icons
    check "killing the Session ends the app" ended
    check "and exits with 0" [ "$status" -eq 0 ]
}
