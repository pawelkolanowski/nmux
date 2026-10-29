# Milestone 8, the config and the themes: runs 37 to 39.

key37() { echo "$1" >>"$TMUX_TMPDIR/keys37"; }
key37b() { echo "$1" >>"$TMUX_TMPDIR/keys37-bad"; }
count37() { grep -c "^selftest: $1$" "$LOG"; }
problems37() { grep -c "^selftest: config-problem " "$LOG"; }
allDefaults37() {
    within 10 logged "config image-storage-limit=320000000" \
        && [ "$(sed -n "s/^selftest: config //p" "$LOG" | tr "\n" " ")" = "$defaults37" ]
}
command37="set -g mouse on ; set -g set-clipboard on ; set -g allow-passthrough on"
# options37 <option>...: each option's global value on the run's server, one line.
options37() { for o in "$@"; do $T show -gv "$o"; done | tr "\n" " "; }
emptyFile37() { within 3 logged "open-config $cfg" && [ -f "$cfg" ] && [ ! -s "$cfg" ]; }
oneProblem37() { logged "config-problem 2 unknown key" && [ "$(problems37)" -eq 1 ]; }
carded37() { within 10 logged "card config-problems 1" && logged "pills a*"; }
goodReload37() { within 3 is 2 count37 "config pill-width=200" && [ "$(problems37)" -eq 1 ]; }
opened37() { within 3 logged "press openConfig" && within 3 logged "open-config $cfg"; }
cardBack37() { within 3 logged "answer cancel" && within 3 is 4 count37 "card config-problems 1"; }

# Run 37: the config. With no file every key logs its default and no card shows, and Cmd+, leaves the folder and an
# empty file. A file with a good line and a misspelt key applies the good one and lists the other on the card; a reload
# of a good file closes it, and the card comes back with the bad line again. Return presses Open Config; Cmd+Q over the
# card asks in its place and Cancel brings it back; Escape presses Dismiss.
run37() {
    $T new-session -d -s a "exec /bin/cat"
    cfg="$XDG_CONFIG_HOME/nmux/config"
    rm -rf "$XDG_CONFIG_HOME"
    : >"$TMUX_TMPDIR/keys37"
    launch 37 NMUX_SELFTEST_KEYS="$TMUX_TMPDIR/keys37"
    defaults37="theme=Fuwafuwa Sakura font-family=SF Mono font-size=14 font-thicken=false option-as-alt=false"
    defaults37="$defaults37 pill-width=136 background-opacity=1 background-blur=0 copy-on-select=false"
    defaults37="$defaults37 clipboard-write=allow clipboard-read=ask tmux-path= tmux-command=$command37"
    defaults37="$defaults37 image-storage-limit=320000000 "
    check "no file logs every default, in order" allDefaults37
    within 10 logged "pills a*"
    check "the default tmux-command turns mouse, set-clipboard and passthrough on" \
        is "on on on " options37 mouse set-clipboard allow-passthrough
    check "and shows no card" not grep -q "^selftest: card " "$LOG"
    key37 "goto open-config"
    check "Cmd+, on a missing file leaves an empty file in a new folder" emptyFile37
    kill "$PID"
    ended
    printf 'pill-width = 200\nfont-szie = 16\ntmux-command = set -g status off\n' >"$cfg"
    $T set -g allow-passthrough off
    : >"$TMUX_TMPDIR/keys37-bad"
    launch 37-bad NMUX_SELFTEST_KEYS="$TMUX_TMPDIR/keys37-bad"
    check "a good line applies" within 10 logged "config pill-width=200"
    check "a set tmux-command replaces the default whole" \
        within 10 is "off off " options37 allow-passthrough status
    check "a misspelt key is one problem, with its line" oneProblem37
    check "and shows on the card once the Session shows" carded37
    printf 'pill-width = 200\n' >"$cfg"
    key37b "goto reload-config"
    check "a reload of a good file logs no problem" goodReload37
    printf 'pill-width = 200\nfont-szie = 16\n' >"$cfg"
    key37b "goto reload-config"
    check "and closed the card, which a bad reload shows again" within 3 is 2 count37 "card config-problems 1"
    key37b "return"
    check "Return presses Open Config" opened37
    check "which leaves the file as it was" is "$(printf "pill-width = 200\nfont-szie = 16")" /bin/cat "$cfg"
    key37b "goto reload-config"
    within 3 is 3 count37 "card config-problems 1"
    key37b "12 100008 71"
    check "Cmd+Q over the card asks on the closing card in its place" within 3 logged "ask closing"
    key37b "escape"
    check "whose Cancel brings the config's card back" cardBack37
    key37b "escape"
    check "Escape presses Dismiss" within 3 logged "press dismiss"
    check "the app still runs" alive
    kill "$PID"
    check "the app quits on SIGTERM" ended
}

key38() { echo "$1" >>"$TMUX_TMPDIR/keys38"; }
last38() { grep "^selftest: theme " "$LOG" | tail -1; }
noProblem38() {
    within 10 logged "pills a*" && ! grep -q "^selftest: config-problem " "$LOG" && ! grep -q "^selftest: card " "$LOG"
}

# Run 38: the theme. With no config the bundled Fuwafuwa Sakura resolves, with its colours. A name found nowhere is the
# fallback and no problem. A pair resolves the side for the window's appearance and follows a switch of it live; a
# user theme of a bundled name shadows that one, and a reload reads the file again.
run38() {
    $T new-session -d -s a "exec /bin/cat"
    themes38=$(cd "$APP/Contents/Resources/themes" && pwd)
    rm -rf "$XDG_CONFIG_HOME"
    launch 38
    check "no config resolves the bundled Fuwafuwa Sakura" \
        within 10 grep -qE "^selftest: theme (light|dark) $themes38/Fuwafuwa Sakura\$" "$LOG"
    check "with its background, foreground and accent" logged "colour background=fbdfef foreground=57466d accent=cf76a4"
    kill "$PID"
    ended
    mkdir -p "$XDG_CONFIG_HOME/nmux/themes"
    printf 'theme = nope\n' >"$XDG_CONFIG_HOME/nmux/config"
    launch 38-nope
    check "a theme found nowhere is the fallback" within 10 grep -qE "^selftest: theme (light|dark) fallback\$" "$LOG"
    check "and no problem" noProblem38
    kill "$PID"
    ended
    printf 'background = #010203\nforeground = #040506\n' >"$XDG_CONFIG_HOME/nmux/themes/Dracula"
    printf 'theme = light:Nord,dark:Dracula\n' >"$XDG_CONFIG_HOME/nmux/config"
    : >"$TMUX_TMPDIR/keys38"
    launch 38-pair NMUX_SELFTEST_KEYS="$TMUX_TMPDIR/keys38"
    within 10 logged "pills a*"
    key38 "appearance light"
    check "a pair in light resolves its light side from the bundle" within 3 logged "theme light $themes38/Nord"
    key38 "appearance dark"
    check "and on a switch to dark its dark side, the user's file over the bundle's" \
        within 3 is "selftest: theme dark $XDG_CONFIG_HOME/nmux/themes/Dracula" last38
    check "with that file's colours and palette 5 as the accent" \
        logged "colour background=010203 foreground=040506 accent=b200b2"
    printf 'background = #0a0b0c\nforeground = #040506\n' >"$XDG_CONFIG_HOME/nmux/themes/Dracula"
    key38 "goto reload-config"
    check "a reload reads the theme file again" \
        within 3 logged "colour background=0a0b0c foreground=040506 accent=b200b2"
    kill "$PID"
    check "the app quits on SIGTERM" ended
}

key39() { echo "$1" >>"$TMUX_TMPDIR/keys39"; }
applies39() { grep -c "^selftest: apply " "$LOG"; }
apply39() { grep "^selftest: apply " "$LOG" | tail -1 | sed "s/^selftest: //"; }
# reload39 <file text>: writes the config, presses Cmd+Shift+, and waits for its apply.
reload39() { printf "$1" >"$cfg39"; n=$(applies39); key39 "43 12000a 3c"; within 3 over "$n" applies39; }
drawbacks39() { grep -c "^selftest: drawback " "$LOG"; }
# drawback39: the shown Session's first blank cell as `<rrggbb> <aa>`.
drawback39() {
    n=$(drawbacks39); key39 drawback
    within 5 over "$n" drawbacks39 && grep "^selftest: drawback " "$LOG" | tail -1 | sed "s/^selftest: drawback //"
}
drawbackColour39() { drawback39 | cut -d " " -f 1; }
background39() { grep "^selftest: colour " "$LOG" | tail -1 | sed "s/.*background=\([0-9a-f]*\) .*/\1/"; }
cells39() { grep "^selftest: cell " "$LOG" | sed "s/^selftest: cell \([0-9]*\)x\([0-9]*\) .*/\1 \2/"; }
beforeFirst39() {
    within 10 logged 'attached $1' \
        && [ "$(grep -n "^selftest: apply launch " "$LOG" | cut -d: -f1)" \
            -lt "$(grep -n "^selftest: attached " "$LOG" | head -1 | cut -d: -f1)" ]
}
larger39() { echo "$(cells39 | head -1) $(cells39 | tail -1)" | awk '{ exit !($3 > $1 && $4 > $2) }'; }
oncePerSession39() {
    within 3 test -f "$TMUX_TMPDIR/sizes39" && sleep 1 && [ "$(wc -l <"$TMUX_TMPDIR/sizes39")" -eq 2 ]
}
halfAlpha39() { a=$(drawback39 | cut -d " " -f 2); [ -n "$a" ] && [ $((0x$a)) -ge 120 ] && [ $((0x$a)) -le 136 ]; }
switched39() { within 3 over "$n" applies39 && [ "$(apply39)" = "apply appearance colours" ]; }

# Run 39: the apply. Fuwafuwa Sakura is on the first frame. Cmd+Shift+, to a theme found nowhere draws the fallback's
# background in both Sessions, the hidden one once shown; font-size 18 measures a larger cell and gives each Session's
# client the logged grid once; background-opacity 0.5 draws the default background at half alpha; a reload with nothing
# changed redoes nothing; a pair follows a switch of the appearance.
run39() {
    $T new-session -d -s a "exec /bin/cat" \; set -t a status off
    $T new-session -d -s b "exec /bin/cat" \; set -t b status off
    rm -rf "$XDG_CONFIG_HOME"
    mkdir -p "$XDG_CONFIG_HOME/nmux"
    cfg39="$XDG_CONFIG_HOME/nmux/config"
    printf 'theme = Fuwafuwa Sakura\n' >"$cfg39"
    : >"$TMUX_TMPDIR/keys39"
    launch 39 NMUX_SELFTEST_KEYS="$TMUX_TMPDIR/keys39"
    check "launch applies everything" within 10 logged "apply launch colours face opacity pills input images"
    check "before the first Session" beforeFirst39
    within 10 logged "probe hold"
    check "the first frame's background is Fuwafuwa Sakura's" is "fbdfef ff" drawback39
    reload39 'theme = nope\n'
    check "a reload to a theme found nowhere redoes the colours" is "apply reload colours" apply39
    check "and draws the fallback's background" is "$(background39) ff" drawback39
    key39 "goto session-2"
    within 3 logged "pills a b*"
    check "in the Session that was hidden too" is "$(background39) ff" drawback39
    $T set-hook -g client-resized \
        "run-shell 'echo #{client_name} #{client_width}x#{client_height} >>$TMUX_TMPDIR/sizes39'"
    reload39 'theme = nope\nfont-size = 18\n'
    check "font-size 18 redoes the face" is "apply reload face" apply39
    check "and measures a wider and taller cell" larger39
    grid39=$(grep "^selftest: grid " "$LOG" | tail -1 | cut -d " " -f 3)
    check "each Session's client gets the logged grid" within 3 is "$grid39" plainSizes
    # tmux expands the hook's client_name as one client for both resizes, so the seam counts them: one per Session.
    check "once per Session" oncePerSession39
    reload39 'theme = nope\nfont-size = 18\nbackground-opacity = 0.5\n'
    check "background-opacity 0.5 redoes the opacity" is "apply reload opacity" apply39
    check "and draws the default background at half alpha" halfAlpha39
    reload39 'theme = nope\nfont-size = 18\nbackground-opacity = 0.5\n'
    check "a reload with nothing changed redoes nothing" is "apply reload none" apply39
    reload39 'theme = light:Nord,dark:Dracula\nfont-size = 18\nbackground-opacity = 0.5\n'
    check "a pair redoes the colours" is "apply reload colours" apply39
    key39 "appearance light"
    sleep 0.5
    n=$(applies39)
    key39 "appearance dark"
    check "and a switch of the appearance redoes them again" switched39
    check "in its dark side's background" is "$(background39)" drawbackColour39
    kill "$PID"
    check "the app quits on SIGTERM" ended
}
