# Vigil

[![Latest release](https://img.shields.io/github/v/release/vdzeer/vigil)](https://github.com/vdzeer/vigil/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/vdzeer/vigil/total)](https://github.com/vdzeer/vigil/releases)
[![CI](https://github.com/vdzeer/vigil/actions/workflows/ci.yml/badge.svg)](https://github.com/vdzeer/vigil/actions/workflows/ci.yml)
[![macOS 13+](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey)](https://github.com/vdzeer/vigil#install)
[![License: MIT](https://img.shields.io/github/license/vdzeer/vigil)](https://github.com/vdzeer/vigil/blob/main/LICENSE)

Vigil is a small menu bar app that keeps your Mac awake. One click stops the display from
sleeping and the Mac from idling to sleep, the way Caffeine does. A second switch lets the Mac
keep running with its lid closed, for example while a long build or a download finishes.

## Features

- **Keep Mac Awake.** Click the eye in the menu bar to switch it on or off. While it is on, the
  display stays on and the Mac does not lock or sleep when idle.
- **Keep Running with Lid Closed.** Right-click (or Control-click) the eye and choose it in the
  menu. The Mac keeps running when you close the lid, and its display turns off behind the lid.
  A monitor connected at that time stays on.
- **Battery guard.** On battery below 15%, lid-closed mode switches itself off, so a closed Mac
  cannot drain to zero. The menu says why until the next change.
- **Nothing left behind.** Quitting Vigil, logging out or a plain `kill` releases everything:
  the Mac sleeps normally again. If Vigil crashes or is force quit while lid-closed mode is on, a
  small watcher it started switches the mode off within a few seconds. Both switches come back
  the way you left them the next time Vigil starts, unless the battery is low.
- **Open at Login**, on after the first launch, can be turned off in the menu or in System
  Settings → General → Login Items.
- **Updates.** Vigil looks for a new version once a day, downloads it and restarts itself with
  it, which takes a second. While the lid is closed in lid-closed mode it waits for the lid to
  open. Check for Updates in the menu looks right away.

The menu bar picture shows the state by its shape, so it stays readable on any wallpaper:

| Picture | Meaning |
| --- | --- |
| Closed eye | The Mac may sleep |
| Open eye | The Mac is kept awake |
| Laptop with a closed eye | Runs with the lid closed; the display may still go to sleep |
| Laptop with an open eye | Runs with the lid closed and is kept awake |

## Install

Download `Vigil-<version>.dmg` from the
[Releases](https://github.com/vdzeer/vigil/releases) page, open it and drag Vigil to
Applications. The app is signed with a Developer ID and notarized by Apple.

Or build it yourself, see [Build from source](#build-from-source).

Requirements: macOS 13 Ventura or later, Apple silicon or Intel.

## Lid-closed mode and the administrator password

Whether a Mac sleeps when its lid closes is a system-wide setting (`pmset disablesleep`) that
only an administrator may change. The first time you switch the mode on, Vigil asks for your
password once, in the standard macOS dialog with Vigil's name on it, and installs this one-line
rule as
`/etc/sudoers.d/vigil`:

```
<your account> ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
```

It lets your account flip exactly that setting without a password, and nothing else. The
script that writes it is `Resources/allow-lid-closed.sh`; it checks the rule with `visudo`
before putting it in place. To take the rule away and restore normal sleep:

```sh
sudo /Applications/Vigil.app/Contents/Resources/allow-lid-closed.sh --remove
```

If Vigil is in `~/Applications` or already gone, the same by hand:

```sh
sudo rm -f /etc/sudoers.d/vigil && sudo pmset -a disablesleep 0
```

Keep in mind:

- A Mac with its lid closed still runs at full speed. Do not carry it in a bag in this mode: it
  gets hot.
- Any program running under your account can also change this one setting while the rule is
  installed. That is the price of not asking for the password every time.

## Privacy

Vigil collects nothing. Its only network connection is the daily update check: it reads
`appcast.xml` from the latest release on GitHub and, when there is a new version, downloads the
disk image from there. No system profile is sent. An update is installed only when its EdDSA
signature matches the key built into the app. To switch automatic updates off:
`defaults write com.vdzeer.vigil SUAutomaticallyUpdate -bool NO`.

Vigil stores its two switches in its own preferences (`com.vdzeer.vigil`).

## Build from source

You need Xcode 26 or later (Swift 6.2).

```sh
git clone https://github.com/vdzeer/vigil.git
cd vigil
scripts/build-app.sh            # builds a universal app, copies it to ~/Applications, starts it
scripts/build-app.sh --no-install
```

A build for your own Mac is signed ad hoc. Set `SIGN_IDENTITY` to sign with one of your
certificates instead.

Checks: `scripts/gates.sh` runs the formatter in lint mode, a build with warnings as errors and
the tests.

The one dependency is [Sparkle](https://sparkle-project.org) for updates, fetched by Swift
Package Manager at the exact version in `Package.swift`.

Release: `scripts/release.sh` builds with a Developer ID, makes a disk image, notarizes and
staples it, and writes `appcast.xml` signed with the update key. The top of the script lists
what it needs; `scripts/release.sh --check` tells you whether it is all in place.

## Layout

| Path | What lives there |
| --- | --- |
| `Sources/VigilCore` | Logic without UI: what the menu shows for each state, the sleep hold, the lid setting, the battery reading, all the words |
| `Sources/Vigil` | The app: the menu bar item and its menu, the glyphs, the login item, updates |
| `Resources` | `Info.plist` and the one-time admin script |
| `Tests` | Unit tests for the core and checks that read the source |
| `scripts` | Build, release and the gates |

## Uninstall

1. Turn off Keep Running with Lid Closed, then quit Vigil.
2. Remove the admin rule (see above), if you ever switched lid-closed mode on.
3. Drag Vigil from Applications to the Trash.

## License

[MIT](LICENSE)
