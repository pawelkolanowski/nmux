#!/bin/sh
# Packs nmux.app into a DMG whose window shows the app, an arrow and a link to Applications, as Mac apps do.
# Usage: Tools/dmg/dmg.sh <nmux.app> <out.dmg>
set -eu
APP=$1 OUT=$2
WORK=build/dmg RW=build/nmux-rw.dmg
rm -rf "$WORK" "$RW" "$OUT" && mkdir -p "$WORK/.background"
cp -R "$APP" "$WORK/" && ln -s /Applications "$WORK/Applications"
# A 1x and a 2x picture in one TIFF, so the background stays sharp on a Retina screen.
sips -s format png -z 400 640 Tools/dmg/background.svg --out "$WORK/bg.png" >/dev/null
sips -s format png -z 800 1280 Tools/dmg/background.svg --out "$WORK/bg@2x.png" >/dev/null
tiffutil -cathidpicheck "$WORK/bg.png" "$WORK/bg@2x.png" -out "$WORK/.background/background.tiff" 2>/dev/null
rm "$WORK/bg.png" "$WORK/bg@2x.png"

hdiutil create -volname nmux -srcfolder "$WORK" -format UDRW -fs HFS+ -quiet "$RW"
MNT=$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | awk -F'\t' '/\/Volumes\// { print $NF }')
trap 'hdiutil detach -quiet "$MNT" 2>/dev/null || true' EXIT
# Finder writes the window's look into the volume's .DS_Store.
osascript <<OSA
tell application "Finder"
    tell disk "$(basename "$MNT")"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {200, 120, 840, 548}
        set opts to icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 128
        set text size of opts to 13
        set background picture of opts to file ".background:background.tiff"
        set position of item "nmux.app" of container window to {170, 190}
        set position of item "Applications" of container window to {470, 190}
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
OSA
sync
hdiutil detach -quiet "$MNT"
trap - EXIT
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -quiet -o "$OUT"
rm -f "$RW"
