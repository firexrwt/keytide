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
dmg="build/Keytide-$version.dmg"
hdiutil create -volname "Keytide $version" -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$dmg" >/dev/null
hdiutil verify "$dmg" >/dev/null
printf '%s\n' "$dmg"
