#!/bin/sh
# The app seam: the self-test build, or APP=<path to .app>, checked through its `selftest:` log and its exit.
# `run.sh 2 3` runs those runs, `run.sh` every run the milestone files hold. Each run starts on a fresh private server
# and the fallback config.
set -u
cd "$(dirname "$0")/../.."
. Tests/seam/lib.sh
for f in Tests/seam/m*.sh; do . "$f"; done

for r in ${*:-$(sed -n 's/^run\([0-9]*\)() {$/\1/p' Tests/seam/m*.sh | sort -n)}; do
    fresh
    if command -v "run$r" >/dev/null; then
        "run$r"
    else
        echo "FAIL run $r, which no milestone file holds"; FAILS=$((FAILS + 1))
    fi
    teardown
done

# The app's default server has its socket here; none means the app never reached it.
check "the default tmux server is untouched" not test -e "$TMUX_TMPDIR/tmux-$(id -u)/default"

[ $FAILS -eq 0 ]
