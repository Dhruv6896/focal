#!/bin/bash
# Builds build/Focal-<version>.dmg: the app, an Applications shortcut and a styled
# drag-to-install window. Run scripts/build.sh first (or let this do it).
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME=Focal
APP="build/$APP_NAME.app"
[ -d "$APP" ] || ./scripts/build.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="build/$APP_NAME-$VERSION.dmg"
WORK=build/dmg
STAGE="$WORK/stage"
RW="$WORK/rw.dmg"
VOLUME="/Volumes/$APP_NAME"

rm -rf "$WORK" "$DMG"
mkdir -p "$STAGE/.background"

# Background art (1x + 2x combined into one HiDPI tiff).
swift scripts/make_dmg_background.swift "$WORK/bg.png" "$WORK/bg@2x.png"
tiffutil -cathidpicheck "$WORK/bg.png" "$WORK/bg@2x.png" -out "$STAGE/.background/background.tiff" >/dev/null

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# Writable image so Finder can save the window layout into it.
[ -d "$VOLUME" ] && hdiutil detach "$VOLUME" -force >/dev/null || true
hdiutil create -srcfolder "$STAGE" -volname "$APP_NAME" -fs HFS+ -format UDRW -ov "$RW" >/dev/null 2>&1
hdiutil attach "$RW" -readwrite -noverify -noautoopen >/dev/null 2>&1

# Window layout: icon view, background, icon positions. Needs permission to control
# Finder; if that's refused, the DMG still works, just unstyled.
if ! osascript <<EOF
tell application "Finder"
    tell disk "$APP_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 860, 548}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 112
        set text size of viewOptions to 13
        set background picture of viewOptions to file ".background:background.tiff"
        set position of item "$APP_NAME.app" of container window to {170, 196}
        set position of item "Applications" of container window to {490, 196}
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF
then
    echo "warning: couldn't style the DMG window (Finder automation not allowed)" >&2
fi

# Custom disk icon. Added after Finder has saved the layout: -srcfolder leaves it out,
# and Finder's layout pass drops it if it's there earlier.
cp build/AppIcon.icns "$VOLUME/.VolumeIcon.icns"
SetFile -a C "$VOLUME"

sync
# Finder can hold the disk for a moment after closing its window; a forced or failed
# detach would lose the last writes (layout, disk icon), so retry politely first.
for attempt in 1 2 3 4 5 6; do
    hdiutil detach "$VOLUME" >/dev/null 2>&1 && break
    [ "$attempt" = 6 ] && { echo "error: couldn't eject $VOLUME" >&2; exit 1; }
    sleep 2
done
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null 2>&1
rm -rf "$WORK"
echo "Built $DMG"
