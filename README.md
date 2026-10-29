<div align="center">
  <img src="assets/icon.png" width="128" height="128" alt="LetMeCatnap icon"/>
  <h1>LetMeCatnap</h1>
  <p><em>我要小喵一下</em></p>
  <p><strong>Take breaks from your screen. Without interrupting your meetings.</strong></p>
  <a href="https://github.com/solitudechn/LetMeCatnap/releases/latest/download/LetMeCatnap.dmg">
    <img src="assets/download-button.svg" alt="Download for Mac">
  </a>
  <p><sub>Free and open source · macOS 13+ · English / 简体中文</sub></p>

  [![Release](https://github.com/solitudechn/LetMeCatnap/actions/workflows/release.yml/badge.svg)](https://github.com/solitudechn/LetMeCatnap/actions/workflows/release.yml)

  <sub><a href="README.zh-CN.md">简体中文</a></sub>
</div>

<div align="center">
  <img src="assets/break-overlay.png" alt="LetMeCatnap break screen" width="480"/>
</div>

LetMeCatnap lives in your menu bar, counts down your work interval, and dims the
screen when it is time to rest your eyes. It stays out of the way while you are in
a call, and it never traps you in a break. The name is 我要小喵一下 — "let me catnap
for a bit" — which is the whole plan.

## How this differs from the original

It began as a fork of [deseven/iCanHazRepose](https://github.com/deseven/iCanHazRepose),
which itself builds on [fikrikarim/repose](https://github.com/fikrikarim/repose).
The meeting detection, the menu-bar-only design and the click-through panel over
full-screen apps come from there. What this build adds or deliberately changes:

|  | iCanHazRepose | LetMeCatnap |
| --- | --- | --- |
| Interface language | English only | English and Simplified Chinese, following the system or switched from the menu — no restart |
| Updates | `Check for Updates…` was a placeholder | Sparkle 2 with an Ed25519-signed feed, checked daily in the background |
| Identity | `wtf.d7.icanhazrepose` | `io.github.solitudechn.letmecatnap` and its own feed, so it installs next to the original with separate settings |
| Pomodoro rhythm | — | a long break every N sessions; manual breaks do not count; the counter resets after 4 hours away |
| When it pauses | one switch: idle for 5 minutes | screen lock or display sleep by default, plus idle, either, or never |
| Break screen | one fixed line | names the break and its length, long breaks in teal, 22 rotating ergonomics tips, countdown fades out |
| Before a break | — | a minute ahead the icon turns into an hourglass and chimes |
| Under the hood | timer logic in the app target, no tests | state machine in `CatnapCore`, tested without AppKit (86 tests) |

## Install

Download the DMG from [Releases](https://github.com/solitudechn/LetMeCatnap/releases).
The build is not notarized, so the first launch may be refused by Gatekeeper
("damaged" or "cannot be verified"). Clear the quarantine flag once:

```sh
xattr -dr com.apple.quarantine /Applications/LetMeCatnap.app
```

Or build it yourself — see [Development](#development).

## How it works

- Pick a work interval (5–90 min) and a break duration (20 sec–10 min). Everything
  else lives in the menu bar: pause, resume, restart, Pomodoro rhythm, every
  setting. There is no preferences window.
- When the interval ends the screen dims and you get one thing to do instead of a
  ticking clock. **Escape always ends a break** — a reminder should never be able
  to trap you.
- **In a call, the break waits.** Detection reads the hardware — CoreMediaIO for
  cameras, CoreAudio for microphones — so it works with Zoom, Meet, FaceTime,
  Teams, Slack huddles or whatever you use next year, with no calendar and no
  per-app setup.
- **Step away and the timer pauses.** By default that means the screen locking or
  the display sleeping; unlocking starts a fresh cycle. Idle-based pausing is
  opt-in, because "no keyboard for five minutes" also describes reading a document
  — which is exactly when you need the reminder.
- **Full-screen apps are respected.** Over a film or a game a small click-through
  panel appears in the middle of the screen; Escape dismisses it.

The break tips are ordinary ergonomics and eye-care advice — the 20-second
distance rule, chin tucks, shoulder-blade squeezes, and a warning against cracking
your neck. Worth doing; not medical treatment.

<div align="center">
  <img src="assets/menu.png" alt="LetMeCatnap menu" width="280"/>
</div>

## Updates

[Sparkle 2](https://sparkle-project.org) handles them, from a feed at
`https://github.com/solitudechn/LetMeCatnap/releases/latest/download/appcast.xml`,
so publishing a release is the only step needed. Checks run once a day in the
background and on demand from **Check for Updates…**; skip a version and Sparkle
stops offering it. Every archive is signed, and the public half of the key sits in
`Info.plist` as `SUPublicEDKey` — anything that does not match is refused.

## Known behaviour

Two things that look like bugs but are not:

- **A three-digit menu bar.** Work intervals accept up to 120 minutes internally
  while the menu offers up to 90, so a value stored by an older build can show as
  `120:00`.
- **The compact panel over a background video.** "Full screen" is decided by
  looking for a window the size of a screen, not by asking which app is in front.

If something else looks wrong, the rotating log at
`~/Library/Logs/LetMeCatnap/LetMeCatnap.log` records every state change, update
check and failure — attach it to a bug report.

## Development

```sh
git clone https://github.com/solitudechn/LetMeCatnap.git
cd LetMeCatnap
./build.sh            # debug build, then launches it
./scripts/verify.sh   # format lint + localization + unit tests + shell syntax
```

`./build.sh ci` produces the same artifacts as a release — universal binary,
`LetMeCatnap.zip`, `LetMeCatnap.dmg` — without uploading or launching anything.

A full **Xcode** is required: Command Line Tools ship neither XCTest nor
`swift format`. If `xcode-select` still points at CLT, `build.sh` finds the newest
`/Applications/Xcode*.app` by itself; the raw `swift test` and `swift format`
commands need `sudo xcode-select -s /Applications/Xcode.app` or a
`DEVELOPER_DIR=…` prefix.

Timing rules, the state machine, settings and the string table live in
`CatnapCore`, so they are tested without AppKit. Every user-visible string is a
`LocKey` in [core/L10n.swift](core/L10n.swift) with both translations in
[core/StringTable.swift](core/StringTable.swift): a missing key is a compile
error, and the tests catch an empty translation or a lost `%@`/`%ld` placeholder.
The release workflow runs all checks before it builds an installer, so a failing
test cannot ship.

## License

MIT. See [LICENSE](LICENSE): both upstream copyright notices are kept verbatim,
with this app's own notice added below them.
