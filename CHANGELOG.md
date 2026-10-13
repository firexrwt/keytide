# Changelog

All notable changes to Keytide, newest first. Each version's section is also the text of its GitHub release.

## 0.1.6 - 2026-10-13

### Fixed

- Words with letters on punctuation keys are corrected: "Юлить" typed as `>kbnm`, "Эхом" as `"[jv` ([#1](https://github.com/firexrwt/keytide/issues/1)).
- Punctuation keys at the end of a word are converted with it: `yj;` becomes "нож", not "но;", and `gj.` becomes "пою", not "по.".
- Sentence punctuation follows the layout: "привет." typed with the other layout's keys (`ghbdtn&` with Apple Russian, `ghbdtn/` with Russian - PC) comes out as "привет.", and `руддщю` as "hello.".
- Smart quotes that Notes and TextEdit put in place of the `'` and `"` keys no longer stop the correction of a word starting with э or Э.

### Changed

- The keystroke path and the field path replace the whole run typed since the last space, punctuation included. A word already known as typed ("hello," or "no;") stays as it is; a typo correction keeps the punctuation as typed.
- The decision for a typed run (`Decision.analyze`) lives in KeytideCore and is covered by tests for both Russian layouts.

## 0.1.5 - 2026-10-13

### Changed

- A single Option press undoes a correction only within 10 seconds of it, time asleep included. Control+D still undoes and protects the word at any time, as before.
- The menu bar icon is dimmed while Keytide is not correcting: paused, without the Accessibility permission, stopped after a failure or without a layout it needs.
- Scroll events no longer pass through Keytide's event tap; each one cost about 0.23 ms of CPU. Option held while scrolling still does not count as a lone Option, and a scroll after a correction still voids its Option undo.
- The keystroke path's word choice, the role of each key and the undo window are decided in KeytideCore and covered by tests.

### Fixed

- Layouts added or removed in System Settings are picked up without restarting Keytide.

## 0.1.4 - 2026-10-12

### Changed

- The bug report is anonymous: apps appear as app1, app2 for the current run, diagnostic steps are numbered instead of timed, and word lengths are recorded only for corrected words.
- Save Report shows the whole report before saving it. It names the two layouts Keytide works with and only counts the others.
- Detailed diagnostics turn themselves off after 30 minutes.

## 0.1.3 - 2026-10-12

### Added

- English interface. Keytide follows the macOS language (English or Russian); a different one can be set for Keytide in System Settings > General > Language & Region > Applications.
- About tab, also opened by About Keytide in the menu: version, signature, links, a diagnostics switch, Save Report and Report a Bug, which opens a GitHub issue form with the version and macOS filled in.

### Changed

- Check for Updates answers in a window: your version is up to date (with the version on GitHub), or a newer one is out, with Update and Later.
- Settings are split into toolbar tabs: General, Words, About.
- Diagnostics stay in memory and are no longer written to the system log. Save Report holds counts, never typed text.

## 0.1.2 - 2026-10-12

### Added

- Hotkey panels such as Raycast: Keytide corrects in the app that owns the input field, not the frontmost app.
- Electron apps such as Claude desktop: Keytide turns on their accessibility tree at the first key typed there, never in password managers, and turns it off again when Keytide quits or is paused or the app is excluded. This costs such an app about 20 MB.
- English contractions typed in the Russian layout are corrected (`дуеэы` -> `let's`, don't, I'm).
- After an update, Settings shows what changed in plain words once; also under What's New in the menu.

### Changed

- Where the field can be read, a word is corrected whole wherever it stands, also when you finish an existing word. Word fragments are never learned.
- Where the field cannot be read, undoing a word that started after a click, an arrow key or a Backspace past its start teaches Keytide nothing.

### Fixed

- TextEdit: the first word of a sentence waits for autocapitalization instead of racing it.

## 0.1.1 - 2026-10-11

### Added

- Self-update. Once a day Keytide asks GitHub for the latest release (can be turned off; Check for Updates works anyway) and updates on one click from the menu. An update is installed only if the dmg and the app inside it are signed with the same certificate as the running app. This is Keytide's first network access.
- Designed dmg window.

### Changed

- Releases are signed with the `Keytide Code Signing` certificate instead of ad-hoc, so updates keep the Accessibility permission.
- First launch: macOS 15 and later need Open Anyway in System Settings > Privacy & Security; right-click > Open no longer works for this.

### Upgrade notes

- Coming from 0.1.0, macOS keeps an old Accessibility entry that no longer matches: remove Keytide in System Settings > Privacy & Security > Accessibility with `-`, add the app with `+` and turn it on. Once; later updates keep it.

## 0.1.0 - 2026-10-11

### Added

- Menu bar app. Words typed in the wrong layout are corrected after a space in both directions from two letters (`ghbdtn` -> `привет`, `lf` -> `да`), case kept, and the system layout is switched for what you type next.
- Obvious typos corrected from three letters, only when the fix is one edit away.
- Single Option undoes the last correction and restores the previous layout. Control+D protects a word from corrections. Both shortcuts are configurable.
- Protected words also work as layout targets: protect `локи` and `kjrb` becomes `локи`.
- Optional learning: two undos of the same word stop correcting it. Learned words can be reviewed and forgotten in Settings.
- Excluded apps (terminals and code editors by default), pause, launch at login, profile export and import.
- In TextEdit, Safari, Chrome, Helium and Codex the field is read and the word replaced in a verified transaction; elsewhere the word being typed is deleted with Backspace and retyped.
- Bundled RU/EN dictionary of about 1.5 million word forms in a 1.4 MB index; the macOS spell checker handles everything else.
- No network access, no text history, no clipboard, no telemetry.
