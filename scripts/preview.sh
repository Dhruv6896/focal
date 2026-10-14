#!/bin/bash
# Debug helper: builds the debug binary into build/FocalPreview.app (a regular,
# non-menu-bar app) and opens the timer panel as a normal window for UI inspection.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build
APP=build/FocalPreview.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/debug/Focal "$APP/Contents/MacOS/Focal"
sed -e 's/com.dhruvbhardwaj.focal/com.dhruvbhardwaj.focal.preview/' \
    -e 's#<string>Focal</string>#<string>Focal Preview</string>#' \
    Resources/Info.plist | perl -0pe 's#<key>CFBundleExecutable</key>\s*<string>Focal Preview</string>#<key>CFBundleExecutable</key>\n    <string>Focal</string>#; s#<key>LSUIElement</key>\s*<true/>#<key>LSUIElement</key>\n    <false/>#' \
    > "$APP/Contents/Info.plist"
[ -f build/AppIcon.icns ] && cp build/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP" 2>/dev/null
pkill -f "FocalPreview.app" 2>/dev/null || true
open "$APP" --args --preview "$@"
