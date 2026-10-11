#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# The app ships optimized: a release-only miscompile once passed every debug test (2026-10-10).
swift test -c release
# Build output stays visible; only its last line, the app path, is captured.
app=$(bash scripts/build-app.sh | tee /dev/stderr | tail -n 1)
target=/Applications/Keytide.app
# Replacing the executable under a running process breaks it, so stop it first.
# Known limit: SIGTERM skips applicationWillTerminate; a settings edit from the last 0.4 s is lost. Quit from the menu while editing.
if pkill -x Keytide; then
    for _ in $(seq 50); do pgrep -xq Keytide || break; sleep 0.1; done
fi
if pgrep -xq Keytide; then echo "Keytide is still running" >&2; exit 1; fi
rm -rf "$target.new" "$target.old"
ditto "$app" "$target.new"
# Two renames instead of delete-then-move: an interrupted install leaves the old app in $target.old, not nothing.
if [ -e "$target" ]; then mv "$target" "$target.old"; fi
mv "$target.new" "$target"
rm -rf "$target.old"
codesign --verify --strict "$target"
codesign -dvvv "$target" 2>&1 | grep '^CDHash='
if [ "$(defaults read dev.firexrwt.keytide DebugInput 2>/dev/null)" = 1 ]; then
    echo "warning: DebugInput diagnostics are on: defaults delete dev.firexrwt.keytide DebugInput" >&2
fi
if codesign -d -r- "$target" 2>&1 | grep -q cdhash; then
    echo "Ad-hoc build: its CDHash changed, so remove the old Keytide from Accessibility, then add it again." >&2
fi
# LaunchServices can return -600 right after the old process exits.
open "$target" || { sleep 2; open "$target"; }
