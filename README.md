<div align="center">
  <img src="assets/icon.png" width="128" height="128" alt="LetMeCatnap icon"/>
  <h1>LetMeCatnap</h1>
  <p><strong>Take breaks from your screen. Without interrupting your meetings.</strong></p>
  <a href="https://github.com/solitudechn/LetMeCatnap/releases/latest/download/LetMeCatnap.dmg">
    <img src="assets/download-button.svg" alt="Download for Mac">
  </a>
  <p><sub>Free and open source. Requires macOS 13+. English / Simplified Chinese.</sub></p>

  [![CI](https://github.com/solitudechn/LetMeCatnap/actions/workflows/ci.yml/badge.svg)](https://github.com/solitudechn/LetMeCatnap/actions/workflows/ci.yml)
  [![Release](https://github.com/solitudechn/LetMeCatnap/actions/workflows/release.yml/badge.svg)](https://github.com/solitudechn/LetMeCatnap/actions/workflows/release.yml)

  <sub><a href="README.zh-CN.md">简体中文</a></sub>
</div>

<br/>

<div align="center">
  <img src="assets/break-overlay.png" alt="LetMeCatnap break screen" width="480"/>
</div>

<br/>

<div align="center">
  <a href="https://github.com/fikrikarim/repose">original code by Fikri Karim</a> ·
  <a href="https://github.com/deseven/iCanHazRepose">upstream author deseven</a> ·
  <a href="https://github.com/solitudechn/LetMeCatnap">this app</a>
</div>

<br/>

> **This started as a fork and grew into its own app.** LetMeCatnap is based on
> [deseven/iCanHazRepose](https://github.com/deseven/iCanHazRepose): it adds an
> English / Simplified Chinese UI and changes a few deliberate behaviours
> (breaks you can always leave, pause triggers you choose, Sparkle for updates).
> It ships under its own name and bundle identifier
> (`io.github.solitudechn.letmecatnap`) with its own signed update feed, so it
> installs next to the original instead of replacing it. Bug reports for *this*
> build belong here; questions about the original belong upstream.

<br/>

LetMeCatnap lives in your menu bar, counts down your work interval, and dims your screen when it's time to rest your eyes. When the break ends, the cycle starts again.

The difference from every other break reminder: **LetMeCatnap detects when you're in a meeting and stays out of your way.** No calendar integration, no app-specific setup. If your camera or mic is active, it knows you're on a call and waits.

The break reminder also respects full screen apps. If you're watching a movie or playing a game, a small panel appears in the middle of the screen that doesn't block any input and can be dismissed by pressing Escape.

## How it works

1. Set your work interval (5–90 min) and break duration (20 sec–10 min)
2. A countdown appears in your menu bar
3. When time's up, you get a gentle reminder to look away — or choose **Take a Break Now** whenever you need one
4. Optionally take a longer break every N completed work sessions with **Pomodoro Rhythm** (manual breaks do not consume a work session)
5. If you're on a call, the break waits until you're done
6. Lock your screen and step away — the timer pauses, and unlocking starts a fresh cycle (**Reminders → Pause When**: lock screen, idle, either, or never)
7. One minute before a break the menu bar icon turns into an hourglass and chimes softly, so the overlay is never a surprise
8. During the break you get a short tip ("look 20 feet away", "roll your shoulders") instead of a ticking clock — on the full-screen overlay the countdown fades out after three seconds; click the ring to bring it back. (The small panel used over full-screen apps keeps its countdown visible, because it is click-through and there would be no way to recall it.)

<div align="center">
  <img src="assets/menu.png" alt="LetMeCatnap menu" width="280"/>
</div>

Everything is in the menu — pause, resume, restart, all settings. No separate preferences window.

## Why the meeting detection actually works

Most break apps check your calendar or look for specific apps running. Both break easily — your calendar doesn't know about the impromptu call your manager just started, and "Zoom is open" doesn't mean you're in a meeting.

LetMeCatnap checks the hardware directly. It uses CoreMediaIO to detect active cameras and CoreAudio for microphones. If something is using your camera or mic right now, you're probably in a call, so it backs off.

This means it works with Zoom, Meet, FaceTime, Teams, Slack huddles, and whatever you end up using next year. Zero configuration.

## When the timer pauses

Most break apps pause on keyboard inactivity — but "no keyboard for two minutes" also describes reading a document, which is exactly when you need the reminder. By default LetMeCatnap waits for the signal that actually means you left: the screen locking, or the display going to sleep. Unlock and you get a fresh work cycle, because a locked screen is a real break.

If you never lock your screen, **Reminders → Pause When** offers the idle-based behaviour instead: pause only when idle (`Idle for 5 Minutes`), on both signals (`Screen Locks or Idle`), or never pause automatically. Idle is opt-in because it is the noisy one — five minutes without input is the threshold, so reading a document is no longer mistaken for leaving.

The break screen hides its countdown after three seconds and puts the guidance front and centre — staring at a ticking number is the opposite of resting your eyes. Click the ring on the full-screen overlay to see the time left again. **Escape always closes a break** — a reminder should never be able to trap you, and over a full-screen app Escape is the only way out (that panel is deliberately click-through, so a Skip button would be unreachable). **Reminders → Show Skip Button** only decides whether the on-screen Skip button is there.

## Install

### Download

**Stable** release — download from the [Releases](https://github.com/solitudechn/LetMeCatnap/releases) page.

The download is not notarized, so the first launch may be blocked by Gatekeeper
("damaged" / "cannot be verified"). Clear the quarantine flag once:

```sh
xattr -dr com.apple.quarantine /Applications/LetMeCatnap.app
```

**Dev** build — every push to `main` is compiled by CI; grab the artifact from the
[latest CI run](https://github.com/solitudechn/LetMeCatnap/actions/workflows/ci.yml).
*(Only use this if you need unreleased functionality or want to help with testing.)*

### Build from source

```
git clone https://github.com/solitudechn/LetMeCatnap.git
cd LetMeCatnap
./build.sh
```

Requires macOS 13+ and a full **Xcode** (Command Line Tools alone cannot expand
the SwiftUI macros). If `xcode-select` still points at CLT after installing
Xcode, `build.sh` picks the newest `/Applications/Xcode*.app` by itself.

`./build.sh` builds a debug binary and launches it; `./build.sh ci` produces the
same artifacts as a release (universal binary, `LetMeCatnap.zip`, `LetMeCatnap.dmg`)
without uploading or launching anything.

## Updates

Updates are handled by [Sparkle 2](https://sparkle-project.org), not by
hand-rolled code:

- the feed is `https://github.com/solitudechn/LetMeCatnap/releases/latest/download/appcast.xml`,
  so publishing a release is the only step needed to ship an update;
- every release archive is signed with an Ed25519 key; the public half lives in
  `Info.plist` as `SUPublicEDKey`, and Sparkle refuses anything that does not
  match;
- Sparkle asks for an administrator password when `/Applications` is not
  writable, instead of failing after the app has already quit.

Checks run once a day in the background and on demand from **Check for
Updates…** in the menu. Skip a version and Sparkle stops offering it.

## Tests and checks

Timing rules, the timer's state machine, settings and the string table live in the
`CatnapCore` module so they can be tested without AppKit:

```
./scripts/verify.sh                 # format lint + localization + unit tests + shell syntax
```

Individually:

```
swift test --filter CatnapCoreTests   # needs a full Xcode (XCTest)
python3 scripts/check-l10n.py         # every key translated, no stray literals
swift format lint --recursive --strict src core Tests
```

All of them run in CI on every push.

## Troubleshooting

The app keeps a rotating log at `~/Library/Logs/LetMeCatnap/LetMeCatnap.log` —
every state change, every update check, every failure. When something looks
wrong, that file is the first thing to attach to a bug report.

```sh
tail -f ~/Library/Logs/LetMeCatnap/LetMeCatnap.log
```

## Known behaviour

Two things that look like bugs but are not:

- **A three-digit menu bar.** Work intervals accept up to 120 minutes internally,
  while the menu only offers up to 90. A value stored by an older build therefore
  shows as `120:00`.
- **The compact panel over a background video.** "Full screen" is decided by
  looking for a window the size of a screen, not by asking which app is in front —
  a full-screen video left running in the background counts too.

## Localization

The UI ships with **English** and **Simplified Chinese** and follows your system
language by default. Override it any time from the menu bar: **Language →
Follow System / English / 简体中文**. The change applies immediately — no restart
needed.

Every user-visible string is a case of `LocKey` in
[`core/L10n.swift`](core/L10n.swift), with both translations in
[`core/StringTable.swift`](core/StringTable.swift). A missing key is a compile
error, and `StringTableTests` fails if a translation is empty, lost its `%@`/`%ld`
placeholder, or kept the English side untranslated.

One exception: Sparkle's own update dialogs follow the *system* language rather
than the in-app **Language** switch — they come from inside the framework, not
from `StringTable`.

## License

MIT. See [LICENSE](LICENSE): the copyright notices of the two upstream authors are
kept verbatim, with this app's own notice added below them. The same three names
appear in the About window under **Author / Upstream author / Original code**.
