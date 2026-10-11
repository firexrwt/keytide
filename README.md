# Keytide

Free, local RU/EN keyboard layout switcher and typo corrector for macOS 13+. [Русская версия](README.ru.md).

Type `ghbdtn ` and get `привет `, type `руддщ ` and get `hello `: after the space Keytide fixes the word, switches the system layout for what you type next, and a single Option press undoes it. A native menu bar app with no network access, no telemetry and no paid dependencies.

## Features

- Wrong-layout words corrected after a space, both directions, from two letters (`lf` -> `да`). Case is kept.
- Obvious typos corrected from three letters, only when the fix is one edit away.
- Single Option undoes the last correction and restores the previous layout. Control+D protects a word from corrections. Both shortcuts are configurable.
- Protected words also work as layout targets: protect `локи` and `kjrb` becomes `локи`.
- Optional learning: two undos of the same word stop correcting it. Learned words can be reviewed and forgotten in Settings.
- Excluded apps (terminals and code editors by default), pause, launch at login, profile export and import.
- Bundled RU/EN dictionary of about 1.5 million word forms in a 1.4 MB memory-mapped index; the macOS spell checker handles everything else.

## How it works

Keytide needs the macOS Accessibility permission to see key presses and edit text.

- In TextEdit, Safari, Chrome, Helium and Codex it reads the field, checks the word and the caret, and replaces the word in a verified transaction.
- Everywhere else it remembers only the word being typed (up to 64 characters, reset at every space) and, after the space, deletes it with Backspace and types the correction. Return never triggers a correction, so a message is sent as typed.
- Nothing is corrected under Secure Input, in password fields, in excluded apps, when the focus is not a text field, when text is selected, or when anything was pressed after the space.

No text history, network, clipboard or telemetry. Diagnostics are opt-in and log stages and lengths, never words.

## Install

1. Download the dmg from [Releases](https://github.com/firexrwt/keytide/releases), open it and drag Keytide to Applications.
2. The app is not notarized. On first launch right-click Keytide and choose Open (or allow it in System Settings > Privacy & Security).
3. Allow Keytide in System Settings > Privacy & Security > Accessibility.

After every update macOS keeps the old permission entry, which no longer matches: remove Keytide there with `-`, add the new app with `+` and turn it on. Toggling the existing switch is not enough.

## Limitations

- Experimental. Each app needs a live check; tests and builds do not prove global typing.
- If an app rewrites a word on the same space (autocorrect, text replacement) in a field Keytide cannot read, the Backspace count can disagree with the text. Where the field is readable, Keytide checks the text first and skips.
- Outside the five apps above, Return does not trigger a correction.

## Build from source

Xcode or the Command Line Tools with Swift 5.9 or newer.

```sh
swift test                 # debug
swift test -c release      # the shipped configuration
bash scripts/build-app.sh  # build/Keytide.app, ad-hoc signed, hardened runtime
bash scripts/install.sh    # release tests, build, replace /Applications/Keytide.app, open
bash scripts/make-dmg.sh   # build/Keytide-<version>.dmg
```

The icon is generated: `swift scripts/make-icon.swift build/AppIcon.iconset && iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns`.

Releases are built by GitHub Actions: pushing a tag `v<version>` that matches `CFBundleShortVersionString` runs the release tests, builds the dmg and drafts a release.

## Dictionaries and license

Keytide is MIT licensed, see [LICENSE](LICENSE). The bundled dictionaries keep their own licenses; sources, terms and the reproducible build command are in [DICTIONARIES.md](Sources/KeytideCore/Resources/DICTIONARIES.md). Normal builds use the checked-in index and download nothing.
