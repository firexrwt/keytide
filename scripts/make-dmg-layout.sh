#!/bin/bash
# One-time: lets Finder lay out the dmg window (size, icon positions, background) and saves its .DS_Store as
# Resources/dmg/DS_Store, which make-dmg.sh copies into every image. Rerun only after changing the background
# geometry. Needs a logged-in Finder and the Automation permission for the calling app; CI never runs it.
set -euo pipefail
cd "$(dirname "$0")/.."
app=build/Keytide.app
[ -d "$app" ] || { echo "Run scripts/build-app.sh first" >&2; exit 1; }
[ ! -e /Volumes/Keytide ] || { echo "/Volumes/Keytide is already mounted" >&2; exit 1; }
work=$(mktemp -d)
trap 'hdiutil detach /Volumes/Keytide -force >/dev/null 2>&1 || true; rm -rf "$work"' EXIT
mkdir -p "$work/stage/.background"
ditto "$app" "$work/stage/Keytide.app"
ln -s /Applications "$work/stage/Applications"
cp Resources/dmg/background.tiff "$work/stage/.background/background.tiff"
# The volume name is part of the layout: make-dmg.sh must use the same "Keytide".
hdiutil create -volname Keytide -srcfolder "$work/stage" -fs HFS+ -format UDRW "$work/layout.dmg" >/dev/null
hdiutil attach "$work/layout.dmg" -readwrite -noverify -noautoopen >/dev/null
# 640x440 content plus the title bar. Positions are icon centres, the same as in make-dmg-background.swift.
# Finder stores an AppleScript position 36 pt lower than given (macOS 27, measured from the saved Iloc records):
# 114 here is a stored icon centre of 150, the one the background is drawn for.
osascript <<'EOF'
on run
    set iconY to 114
    tell application "Finder"
        tell disk "Keytide"
            open
            set w to container window
            set current view of w to icon view
            set toolbar visible of w to false
            set statusbar visible of w to false
            set pathbar visible of w to false
            set the bounds of w to {200, 120, 840, 592}
            set viewOptions to icon view options of w
            set arrangement of viewOptions to not arranged
            set icon size of viewOptions to 112
            set text size of viewOptions to 12
            set background picture of viewOptions to file ".background:background.tiff"
            set position of item "Keytide.app" of w to {136, iconY}
            set position of item "Applications" of w to {504, iconY}
            -- Below the visible area: only seen by people who show hidden files.
            set position of item ".background" of w to {320, 640}
            close
            open
            update without registering applications
            delay 2
            close
        end tell
    end tell
end run
EOF
# Finder writes the window record (bwsp) some time after the close.
for _ in $(seq 40); do /usr/bin/grep -q bwsp /Volumes/Keytide/.DS_Store 2>/dev/null && break; sleep 0.5; done
/usr/bin/grep -q bwsp /Volumes/Keytide/.DS_Store || { echo "Finder did not save the window record" >&2; exit 1; }
cp /Volumes/Keytide/.DS_Store Resources/dmg/DS_Store
printf '%s\n' Resources/dmg/DS_Store
