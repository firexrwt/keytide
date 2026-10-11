#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
bin=$(swift build -c release --show-bin-path)
app="$PWD/build/Keytide.app"
mkdir -p "$app/Contents/MacOS"
mkdir -p "$app/Contents/Resources"
cp "$bin/Keytide" "$app/Contents/MacOS/Keytide"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
ditto "$bin/Keytide_KeytideCore.bundle" "$app/Contents/Resources/Keytide_KeytideCore.bundle"
# Hardened runtime: no DYLD injection into the process that holds the Accessibility grant.
codesign --force --sign - --options runtime --identifier dev.firexrwt.keytide "$app"
codesign --verify --strict "$app"
printf '%s\n' "$app"
