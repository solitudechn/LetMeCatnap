<div align="center">
  <img src="assets/icon.png" width="128" height="128" alt="iCanHazRepose icon"/>
  <h1>iCanHazRepose</h1>
  <p><strong>Take breaks from your screen. Without interrupting your meetings.</strong></p>
  <a href="https://github.com/solitudechn/iCanHazRepose/releases/latest/download/iCHR.dmg">
    <img src="assets/download-button.svg" alt="Download for Mac">
  </a>
  <p><sub>Free and open source. Requires macOS 13+. 简体中文界面。</sub></p>

  [![CI](https://github.com/solitudechn/iCanHazRepose/actions/workflows/ci.yml/badge.svg)](https://github.com/solitudechn/iCanHazRepose/actions/workflows/ci.yml)
  [![Release](https://github.com/solitudechn/iCanHazRepose/actions/workflows/release.yml/badge.svg)](https://github.com/solitudechn/iCanHazRepose/actions/workflows/release.yml)
</div>

<br/>

<div align="center">
  <img src="assets/break-overlay.png" alt="iCanHazRepose break screen" width="480"/>
</div>

<br/>

<div align="center">
  <a href="https://github.com/fikrikarim/repose">originally created by Fikri Karim</a> ·
  <a href="https://github.com/deseven/iCanHazRepose">maintained by deseven</a> ·
  <a href="https://github.com/solitudechn/iCanHazRepose">简体中文 fork</a>
</div>

<br/>

> **This is a fork.** It adds an English / 简体中文 UI on top of
> [deseven/iCanHazRepose](https://github.com/deseven/iCanHazRepose) and ships its own
> downloads and auto-updates. For anything that is not about the localization,
> please use the upstream repository.

<br/>

iCanHazRepose lives in your menu bar, counts down your work interval, and dims your screen when it's time to rest your eyes. When the break ends, the cycle starts again.

The difference from every other break reminder: **iCanHazRepose detects when you're in a meeting and stays out of your way.** No calendar integration, no app-specific setup. If your camera or mic is active, it knows you're on a call and waits.

The break reminder also respects full screen apps. If you're watching a movie or playing a game a small panel appears in the middle of the screen that doesn't block any input and can be dismissed by pressing Escape.

## How it works

1. Set your work interval (5–90 min) and break duration (20 sec–10 min)
2. A countdown appears in your menu bar
3. When time's up, you will receive a gentle reminder to look away — or choose **Take a Break Now / 立即休息** whenever you need one
4. Optionally take a longer break every N completed work sessions with **Pomodoro Rhythm / 番茄节奏** (manual breaks do not consume a work session)
5. If you're on a call, the break waits until you're done
6. If you step away from your computer, the timer pauses and resets when you return

<div align="center">
  <img src="assets/menu.png" alt="iCanHazRepose menu" width="280"/>
</div>

Everything is in the menu — pause, resume, restart, all settings. No separate preferences window.

## Why the meeting detection actually works

Most break apps check your calendar or look for specific apps running. Both break easily — your calendar doesn't know about the impromptu call your manager just started, and "Zoom is open" doesn't mean you're in a meeting.

iCanHazRepose checks the hardware directly. It uses CoreMediaIO to detect active cameras and CoreAudio for microphones. If something is using your camera or mic right now, you're probably in a call, so it backs off.

This means it works with Zoom, Meet, FaceTime, Teams, Slack huddles, and whatever you end up using next year. Zero configuration.

## Smart idle detection

iCanHazRepose also detects when you've stepped away from your computer. If there's no keyboard or mouse activity for 60 seconds plus your configured short-break duration, the timer pauses — and resets to a full work cycle when you return, since you already took a real break.

It's smart about passive screen use too: if you're watching a video (where apps keep the display awake), the timer keeps running so you still get break reminders.

## Install

### Download

**Stable** release — download from the [Releases](https://github.com/solitudechn/iCanHazRepose/releases) page.

The download is not notarized, so the first launch may be blocked by Gatekeeper
("damaged" / "cannot be verified"). Clear the quarantine flag once:

```sh
xattr -dr com.apple.quarantine /Applications/iCanHazRepose.app
```

**Dev** build — every push to `main` is compiled by CI; grab the artifact from the
[latest CI run](https://github.com/solitudechn/iCanHazRepose/actions/workflows/ci.yml).
*(only use this if you need unreleased functionality or want to help with testing)*

### Build from source

```
git clone https://github.com/solitudechn/iCanHazRepose.git
cd iCanHazRepose
./build.sh
```

Requires Xcode 15+ and macOS 13+.

## Localization / 界面语言

The UI ships with **English** and **简体中文** and follows your system language by default. Override it any time from the menu bar: **Language / 语言 → 跟随系统 / English / 简体中文**. The change applies immediately — no restart needed.

界面默认跟随系统语言（英文 / 简体中文），也可随时在菜单栏 **语言** 里手动切换，无需重启应用。

All translatable strings live in [`src/L10n.swift`](src/L10n.swift).

## Releasing

```sh
git tag v1.0.4 && git push origin v1.0.4
```

The `Release` workflow builds a universal `.app`, zips it as `iCHR.zip`, creates
`iCHR.dmg`, stamps the version from the tag into `Info.plist`, and publishes a
GitHub Release titled `iCanHazRepose 1.0.4`.

Two details matter for the in-app updater — do not change them:

- the release title must contain `iCanHazRepose x.y.z` (or `iCHR x.y.z`);
- the zip asset must be named exactly `iCHR.zip`.

Add `MACOS_CERT_P12`, `MACOS_CERT_PASSWORD`, `NOTARY_APPLE_ID`, `NOTARY_TEAM_ID`
and `NOTARY_APP_PASSWORD` as repository secrets to get a signed + notarized
build; without them the artifacts are ad-hoc signed.

## Help & Support

- [File an issue](https://github.com/solitudechn/iCanHazRepose/issues/new) for bugs, suggestions, or questions about this fork
- [Upstream issues](https://github.com/deseven/iCanHazRepose/issues) for the app itself
- Discord: https://discord.gg/YE9KyTXRPt
- Reddit: https://www.reddit.com/r/iCanHazApps
