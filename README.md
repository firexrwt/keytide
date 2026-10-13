# Keytide

Free, local RU/EN keyboard layout switcher and typo corrector for macOS 13+. [Русская версия](README.ru.md).

Type `ghbdtn ` and get `привет `, type `руддщ ` and get `hello `: after the space Keytide fixes the word, switches the system layout for what you type next, and a single Option press undoes it. A native menu bar app with no telemetry and no paid dependencies; its only network access is the update check.

## Features

- Wrong-layout words corrected after a space, both directions, from two letters (`lf` -> `да`). Case is kept. English contractions typed in the Russian layout are fixed too (`дуеэы` -> `let's`).
- Obvious typos corrected from three letters, only when the fix is one edit away.
- Single Option, within 10 seconds of a correction, undoes it and restores the previous layout. The menu bar icon dims while Keytide is not correcting. Control+D protects a word from corrections. Both shortcuts are configurable.
- Protected words also work as layout targets: protect `локи` and `kjrb` becomes `локи`.
- Optional learning: two undos of the same word stop correcting it. Learned words can be reviewed and forgotten in Settings.
- Excluded apps (terminals and code editors by default), pause, launch at login, profile export and import.
- Updates itself on one click from the menu and keeps the Accessibility permission (from 0.1.1). Check for Updates answers in a window: up to date (with the version on GitHub) or a newer version with an Update button. After an update, Settings shows what changed in plain words once (also under What's New in the menu).
- English and Russian interface, following the macOS language (a different one can be set for Keytide in System Settings > General > Language & Region > Applications).
- About tab (also About Keytide in the menu): version, links, a diagnostics switch, Save Report and Report a Bug, which opens the GitHub issue form with the version and macOS filled in.
- Bundled RU/EN dictionary of about 1.5 million word forms in a 1.4 MB memory-mapped index; the macOS spell checker handles everything else.

## How it works

Keytide needs the macOS Accessibility permission to see key presses and edit text.

- In TextEdit, Safari, Chrome, Helium and Codex it reads the field, checks the word and the caret, and replaces the word in a verified transaction.
- Everywhere else it remembers only the word being typed (up to 64 characters, reset at every space) and, after the space, deletes it with Backspace and types the correction. Return never triggers a correction, so a message is sent as typed.
- Where such a field can still be read (Raycast, most native apps, Electron apps like Claude desktop), Keytide reads the word before the caret at the space, so a word is corrected whole wherever it stands, even when you finish an existing word, and fragments are never learned. For Electron apps it turns on their accessibility tree (`AXManualAccessibility`) at the first key you type there, never in password managers, and turns it off again when Keytide quits or the app is excluded; this costs that app about 20 MB. Where a field cannot be read at all, the typed word is still corrected, but undoing a word that started after a click, an arrow key or a Backspace past its start teaches Keytide nothing, since it may be part of a longer word.
- Nothing is corrected under Secure Input, in password fields, in excluded apps, when the focus is not a text field, when text is selected, or when anything was pressed after the space.

Nothing Keytide reads is sent anywhere (its only network access is the update check, below), and there is no telemetry or text history. Keytide holds what it reads only as long as the correction needs it: at most the 160 characters before the caret, or a short field of up to 4,000 characters whole when it cannot give a range of its text; nothing it reads is stored or logged. Where a field shows its caret but hides its text from accessibility (apps that draw text themselves) and a word was started after you moved the caret, Keytide selects the text before the caret (the word and up to 32 characters before it), copies it and at once puts your clipboard back, every item and format; a clipboard it could not read back in full (over 16 items or 8 MB, or data its owner does not provide) is left alone, and so is a clipboard macOS asks about or denies to Keytide. In our measurements the copied text stays on the clipboard for 4 to 23 milliseconds. A clipboard history app, sync tool or Universal Clipboard may still catch it in that moment; turn this off in Settings ("Read words through the clipboard"). A copy marked as concealed (password managers) is never touched, and where nothing shows a caret no keys are sent. Diagnostics are opt-in (About > Detailed diagnostics, off again after 30 minutes) and record numbered decision steps only: no typed text, no word lengths except for corrected words, no app names (apps appear as app1, app2) and no times. They stay in memory and are not written to the system log. Save Report shows the whole anonymous report before saving it (versions, settings, the two layouts in use, counts and those steps); nothing is sent anywhere, you attach the file yourself.

The only network access is updates: once a day Keytide asks api.github.com for the latest release (turn it off in Settings; "Check for updates" in the menu works anyway), and it downloads a release from github.com (served from GitHub's storage on *.githubusercontent.com) only when you click "Update". An update is installed only if both the dmg and the app inside it are signed with the same certificate as the running app. If Keytide rejects an update for its signature, do not install that version by hand.

## Install

1. Download the dmg from [Releases](https://github.com/firexrwt/keytide/releases), open it and drag Keytide to Applications.
2. The app is not notarized. If macOS refuses to open it, go to System Settings > Privacy & Security and click Open Anyway (right-click > Open no longer works for this since macOS 15).
3. Allow Keytide in System Settings > Privacy & Security > Accessibility.

Updates from the menu keep the permission. Coming from 0.1.0, or after installing a build signed with another certificate, macOS keeps an old permission entry that no longer matches: remove Keytide there with `-`, add the app with `+` and turn it on. Toggling the existing switch is not enough.

## Limitations

- Experimental. Each app needs a live check; tests and builds do not prove global typing.
- If an app rewrites a word on the same space (autocorrect, text replacement) in a field Keytide cannot read, the Backspace count can disagree with the text. Where the field is readable, Keytide checks the text first and skips.
- Outside the five apps above, Return does not trigger a correction.

## Build from source

Xcode or the Command Line Tools with Swift 5.9 or newer.

```sh
swift test                 # debug
swift test -c release      # the shipped configuration
bash scripts/build-app.sh  # build/Keytide.app, hardened runtime, signed (see below)
bash scripts/install.sh    # release tests, build, replace /Applications/Keytide.app, open
bash scripts/make-dmg.sh   # build/Keytide-<version>.dmg
```

The icon is generated: `swift scripts/make-icon.swift build/AppIcon.iconset && iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns`.

The dmg window is generated too. `swift scripts/make-dmg-background.swift build/dmg-bg && tiffutil -cathidpicheck build/dmg-bg/background.png build/dmg-bg/background@2x.png -out Resources/dmg/background.tiff` draws the background; `bash scripts/make-dmg-layout.sh` lets Finder save the window layout once into `Resources/dmg/DS_Store` (rerun it only when the geometry changes). `make-dmg.sh` just copies both, so CI needs no Finder.

`build-app.sh` and `make-dmg.sh` sign with the identity named `Keytide Code Signing` when the keychain has its private key, otherwise ad-hoc: an ad-hoc build loses the Accessibility permission on every rebuild and cannot update itself or be offered as an update.

Releases are built by GitHub Actions: pushing a tag `v<version>` that matches `CFBundleShortVersionString` runs the release tests, signs the app and the dmg, checks both against the pinned certificate and drafts a release whose text is that version's section of [CHANGELOG.md](CHANGELOG.md) (the tests fail without it). The job runs in the `release` environment, which holds the `KEYTIDE_CERT_P12` and `KEYTIDE_CERT_PASSWORD` secrets and waits for the owner's approval.

## Signing certificate

Official builds are signed with the self-signed certificate `Keytide Code Signing`, SHA-256 fingerprint:

```
1D:FC:6B:08:D3:DB:A2:84:2A:6A:BE:E8:A7:D1:D5:91:F1:16:53:82:78:BC:C4:B4:0C:9A:5D:C6:B8:E4:98:90
```

Check a download with `codesign -dvv Keytide.app` (Authority) and `codesign -d -r- Keytide.app` (the requirement names the certificate's SHA-1, `f17aa23f772d72310797b7e3aabd4db522de9923`; the certificate is valid until 2046). The private key exists only in the `release` environment and an offline backup. A self-signed certificate cannot be revoked: if the key is ever lost or stolen, this README and the release notes will say so, and a new certificate will need one manual reinstall and a new Accessibility grant.

## Dictionaries and license

Keytide is MIT licensed, see [LICENSE](LICENSE). The bundled dictionaries keep their own licenses; sources, terms and the reproducible build command are in [DICTIONARIES.md](Sources/KeytideCore/Resources/DICTIONARIES.md). Normal builds use the checked-in index and download nothing.
