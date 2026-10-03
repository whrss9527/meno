<div align="center">
  <img src="docs/icon.png" width="128" height="128" alt="Meno icon">
  <h1>Meno</h1>
  <p><strong>A calm menu bar, made with glass</strong></p>
  <p>A menu bar manager for macOS. Native Swift, Liquid Glass, free and open source.</p>
  <p>
    <a href="https://github.com/whrss9527/meno/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/whrss9527/meno?include_prereleases&label=release&color=7C6CFF"></a>
    <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111827?logo=apple&logoColor=white">
    <img alt="Liquid Glass" src="https://img.shields.io/badge/UI-Liquid%20Glass-7C6CFF">
    <a href="LICENSE"><img alt="GPL-3.0" src="https://img.shields.io/badge/license-GPL--3.0-2563EB"></a>
  </p>
  <p>
    <a href="https://github.com/whrss9527/meno/releases/latest"><b>Download</b></a> ·
    <a href="https://github.com/whrss9527/meno/releases">Release notes</a> ·
    <a href="README.zh-CN.md">简体中文</a>
  </p>
</div>

### **Meno** /ˈmeː.no/

Italian for "less".

On sheet music, *meno mosso* means "slow down a little, no rush."

Your menu bar should hold a little less, too: keep what you use, tuck away what you don't, and call it back when you need it.

And **Meno** is just one letter away from **Menu** — a little less, just right.

## Features

- **Tuck away what you rarely need:** Visible, Hidden, and a Stash for the icons you almost never touch.
- **Bring them back your way:** a click, a hover, a swipe or a shortcut. Quick Open finds any item from the keyboard.
- **Glass all the way:** a Shelf below the menu bar and a Spotlight-style palette, in Liquid Glass on macOS 26.
- **A menu bar that reads the room:** rules and scenes kick in when the mic is on, a display is plugged in or you're on battery.
- **Zen in one keystroke:** clear every app icon for screenshots, recordings and talks.
- **Private:** no analytics, no accounts. Meno only goes online for updates.

## Install

Meno runs on macOS 14 Sonoma or later, on Apple silicon and Intel.

With [Homebrew](https://brew.sh):

```sh
brew install --cask whrss9527/tap/meno
```

Or by hand:

1. Download `Meno.zip` from the [latest release](https://github.com/whrss9527/meno/releases/latest), unzip it and move Meno.app to *Applications*.
2. Open it and allow Meno in *System Settings › Privacy & Security › Accessibility*.
3. When a new version is out, choose *Install and Relaunch* and Meno updates itself.

Releases from 0.10.0 on are signed with a Developer ID and notarized, so they open with a double-click.

## Quick start

| Do this | And |
| --- | --- |
| Hold ⌘ and drag icons across Meno's dividers | Sort them into Visible, Hidden and the Stash |
| Click the Meno icon or an empty part of the menu bar (hovering and swiping down can be turned on in Settings) | Hidden items come back |
| Set a Quick Open shortcut in *Settings › Hotkeys* and press it | Find and open any menu bar item from the keyboard |
| Turn on Zen | Every app icon is gone, for screenshots, recordings and talks |
| Add a rule in Meno's Settings | The menu bar follows your mic, displays, power or network |

## Docs

- [Guide](docs/guide.md): installing and updating, every feature, `meno://` links, how hiding works, footprint, permissions and privacy, troubleshooting
- [Development](docs/development.md): building, project layout, tests and releases
- [Release notes](https://github.com/whrss9527/meno/releases)

## Support

Meno is free and open source. If you like it, a ⭐ star means a lot, or you can buy me a coffee with WeChat.

<p align="center"><img src="docs/donate-wechat.png" width="240" alt="WeChat tip code: buy me a coffee"></p>

## License

Copyright © 2026 whrss9527

Meno is free software, released under the [GNU General Public License v3.0](LICENSE). You may use, study, change and share it. If you distribute Meno or a modified version, you must make its source code available under the same license.

The name "Meno" and the Meno icon are not licensed under the GPL (section 7(e)). You may use them to refer to Meno and when sharing unmodified copies, but a modified version you distribute needs its own name and icon.

Contributions are accepted under the contributor license agreement in [CONTRIBUTING.md](CONTRIBUTING.md).

Meno 0.1.0 was released under the MIT License, and that version stays available under it.

---

<div align="center">
  <p><b>Also living in the menu bar</b></p>
  <a href="https://github.com/whrss9527/pop"><img src="https://raw.githubusercontent.com/whrss9527/whrss9527/master/assets/cards/pop.svg" width="30%" alt="Pop"></a>
  <a href="https://github.com/whrss9527/stox"><img src="https://raw.githubusercontent.com/whrss9527/whrss9527/master/assets/cards/stox.svg" width="30%" alt="Stox"></a>
  <a href="https://github.com/whrss9527/proxi"><img src="https://raw.githubusercontent.com/whrss9527/whrss9527/master/assets/cards/proxi.svg" width="30%" alt="Proxi"></a>
</div>
