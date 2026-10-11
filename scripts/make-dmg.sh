#!/bin/bash
# Packs build/Keytide.app into build/Keytide-<version>.dmg with an Applications link for drag-and-drop install.
set -euo pipefail
cd "$(dirname "$0")/.."
app=build/Keytide.app
[ -d "$app" ] || { echo "Run scripts/build-app.sh first" >&2; exit 1; }
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/Keytide.app"
ln -s /Applications "$stage/Applications"
# Window design: background plus the layout Finder saved once (scripts/make-dmg-layout.sh). The layout finds the
# background by its path on a volume named exactly "Keytide", so the version stays out of the volume name.
mkdir "$stage/.background"
cp Resources/dmg/background.tiff "$stage/.background/background.tiff"
cp Resources/dmg/DS_Store "$stage/.DS_Store"
chflags hidden "$stage/.background"
dmg="build/Keytide-$version.dmg"
hdiutil create -volname Keytide -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$dmg" >/dev/null
hdiutil verify "$dmg" >/dev/null
# Installed apps check this signature before they mount an update, with the same requirement as the app itself.
source scripts/identity.sh
if [ "$sign" = - ]; then
    echo "warning: '$identity' not found, dmg left unsigned: installed apps will refuse it as an update" >&2
else
    codesign --force --sign "$sign" --identifier dev.firexrwt.keytide "$dmg"
    codesign --verify --strict "$dmg"
fi
printf '%s\n' "$dmg"
