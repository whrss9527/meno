<div align="center">
  <img src="docs/icon.png" width="128" height="128" alt="Meno icon">
  <h1>Meno</h1>
  <p><strong>A calm menu bar, made with glass.</strong></p>
  <p>A native macOS menu bar manager with a Liquid Glass interface.</p>
  <p>
    <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111827?logo=apple&logoColor=white">
    <img alt="Swift" src="https://img.shields.io/badge/Swift-5.10%2B-F05138?logo=swift&logoColor=white">
    <img alt="Liquid Glass" src="https://img.shields.io/badge/UI-Liquid%20Glass-7C6CFF">
    <a href="LICENSE"><img alt="GPL-3.0 License" src="https://img.shields.io/badge/license-GPL--3.0-2563EB"></a>
  </p>
  <p><a href="README.zh-CN.md">简体中文</a></p>
</div>

Meno tucks away the menu bar icons you rarely need and brings them back the moment you want them — with a click, a hover, a swipe or a shortcut. Everything stays reachable from the keyboard, and the menu bar can adapt to what you are doing.

## Features

### Hide and reveal

- **Three sections.** *Visible* items are always shown. *Hidden* items appear on demand. The *Stash* is for items you almost never need: they never appear in the menu bar, only in the Shelf, Quick Open or with ⌥-click.
- **Many ways to reveal:** click the Meno icon, click or hover over an empty part of the menu bar, scroll or swipe down over it, or press a global shortcut.
- **Smart re-hiding:** after a delay, when you switch apps or click elsewhere, or when the pointer leaves the menu bar. Items stay put while one of their menus is open.
- **Room when you need it:** Meno can clear the frontmost app's menus while items are revealed, so a long row of icons fits.

### Glass interface

- **Shelf:** a Liquid Glass bar below the menu bar that shows hidden items. Useful next to the camera housing, where the menu bar runs out of space. With *Automatic* reveal, Meno picks the Shelf only when items would not fit. Visible items that macOS put behind the camera housing come first, so they can still be clicked.
- **Quick Open:** a Spotlight-style palette (fuzzy search, pinyin and initials included) to open any menu bar item from the keyboard. ↩ opens, ⌘↩ opens the secondary menu, ⌥↩ reveals the item in place, ⌘1–⌘9 pick a result.
- **Layout editor:** drag items between the Visible, Hidden and Stash lanes, or next to other items to reorder them. Meno performs the ⌘-drags for you. Items can be renamed, which helps with items that macOS reports without a useful name.
- **Show when it changes:** pick hidden items that Meno shows for a moment when their icon or text changes, for example when a sync fails.
- Liquid Glass on macOS 26 and later; a frosted-glass look with a light rim on macOS 14 and 15.

### Make it yours

- **Rules:** "When a microphone is in use, turn on Zen." Conditions include the frontmost or running app, a microphone or camera in use, battery, power and Low Power Mode, external or specific displays, the time of day and being offline. Actions reveal or hide sections, apply a scene, turn on Zen, or move a specific item — and can be undone automatically. Moves wait until you are not using the mouse and keyboard.
- **Scenes:** save arrangements such as *Work*, *Home* or *Presenting* and switch between them from the menu or with a rule.
- **Zen:** one shortcut clears every app icon, leaving only system status. Great for screenshots, recordings and talks.
- **Item shortcuts:** open a specific item (Wi-Fi, a VPN, a timer…) from anywhere, even while it is hidden.
- **Links:** `meno://` links let Shortcuts, launchers and scripts show or hide items, switch Zen, apply a scene or open an item. Scenes and items offer *Copy Link*.
- **Markers:** add spaces, thin lines, dots, SF Symbols or short text labels to the menu bar to group your items.
- **Insights:** private, on-device statistics — how often you reveal, your most used items, and suggestions such as "you opened this 12 times this week while it was hidden — keep it visible?".
- **New arrivals:** when an app adds a new icon, Meno can ask you, hide it or stash it.
- **Appearance:** choose the Meno icon, divider style, Shelf glass and tint, a menu bar tint with gradient, border, shadow and split "island" shapes (experimental), and system-wide icon spacing (beta).
- English and Simplified Chinese.

## Requirements

- macOS 14 Sonoma or later. Liquid Glass needs macOS 26 and a build made with Xcode 26.
- Building needs Xcode 16 or later (Xcode 26 for Liquid Glass).

## Download

Download `Meno.zip` from the [latest release](https://github.com/whrss9527/meno/releases/latest), unzip it and move Meno.app to *Applications*. The app is universal (Apple silicon and Intel) and signed ad hoc, so macOS asks for confirmation on first launch: right-click Meno.app and choose *Open*, or run `xattr -dr com.apple.quarantine /Applications/Meno.app`.

New versions are published by pushing a `v*` tag or by running the *Release* workflow with a version number.

After an update, macOS may keep an entry for the previous build in the Accessibility list that no longer counts. Meno then opens *Settings › Permissions*, where *Reset and Grant Again* replaces the entry. To keep the permission across updates altogether, sign releases with a fixed certificate: run `scripts/create-signing-certificate.sh` once and add the two secrets it prints, `MACOS_CERTIFICATE_P12` and `MACOS_CERTIFICATE_PASSWORD`, to the repository. The *Release* workflow then signs with it.

## Build and run

```bash
git clone https://github.com/whrss9527/meno.git
cd meno
make run        # builds build/Meno.app and opens it
make install    # copies Meno.app to /Applications
make test       # unit tests
```

`make app` builds a release app bundle in `build/`. Set `UNIVERSAL=1` for an arm64 + x86_64 binary and `SIGN_IDENTITY="Developer ID Application: …"` to sign with your certificate.

The default build is signed ad hoc. macOS ties privacy permissions to the signature, so after rebuilding you may have to remove Meno from *System Settings › Privacy & Security › Accessibility* and add it again. Signing with a real certificate avoids this.

You can also open `Package.swift` in Xcode to edit and debug. When Meno runs outside an app bundle, macOS attributes permissions to Xcode instead of Meno, so use `make run` to try permission-related features.

## Permissions

| Permission | Needed for |
| --- | --- |
| **Accessibility** (required) | Reading menu bar items, opening them from the Shelf, Quick Open and shortcuts, and arranging them with ⌘-drag. |
| **Screen Recording** (optional) | Showing the real artwork of hidden items and noticing when their icons change (macOS 14–26). Without it Meno shows app icons. Only menu bar items are captured. |

Rules about a microphone or camera in use only ask macOS whether a device is running, which needs no permission. Meno never records anything.

Meno has no analytics or accounts. It only goes online to ask GitHub for the latest release: when you click *Check for Updates* in *Settings › About*, or once a day if you turn that on in *General*. Settings and statistics live in `~/Library/Application Support/Meno`.

## Links

| Link | Does |
| --- | --- |
| `meno://show`, `meno://show/all` | Shows the hidden items, or everything including the Stash |
| `meno://hide`, `meno://toggle` | Hides them again, or switches |
| `meno://zen`, `meno://zen/on`, `meno://zen/off` | Switches Zen, turns it on or off |
| `meno://scene/Work` | Applies the scene named *Work* |
| `meno://open/Wi-Fi`, `meno://open/Wi-Fi?menu=secondary` | Opens a menu bar item by name |
| `meno://quick-open`, `meno://shelf`, `meno://settings/rules` | Opens Quick Open, the Shelf or a Settings pane |

For example, `open meno://zen/on` in Terminal, or an *Open URLs* action in Shortcuts. For names with spaces or other scripts, *Copy Link* gives a link that is already encoded.

## How it works

Meno adds small dividers to the menu bar: a single chevron starts the Hidden section, a double chevron the Stash. Everything left of a divider belongs to that section. Hold ⌘ and drag icons across the dividers, or use the Layout editor.

To hide a section, its divider grows until the items to its left no longer fit:

- **Wide engine (macOS 14–26):** one divider grows far past the edge of the screen.
- **Stepped engine (macOS 27):** the macOS 27 menu bar drops items wider than about half of the display, and large length changes do not push neighbours along. Meno grows the divider together with a few helper spacers, each just below that limit, in 40 pt steps. Items pushed out go into the system overflow menu. You can choose the engine in *Settings › General › Advanced*.

Menu bar items are read through each app's accessibility tree, which works on every supported macOS version, including the single-window menu bar of macOS 27.

## Good to know

- Moving items simulates ⌘-drags, so Meno briefly takes over the pointer and puts it back afterwards. Items that are not currently on screen cannot be dragged; reveal them first. The clock and the Control Center icon cannot be moved.
- Icon spacing uses the `NSStatusItemSpacing` and `NSStatusItemSelectionPadding` preferences, which apps read at launch. Applying it relaunches apps that own menu bar items.
- The menu bar tint is drawn behind the menu bar and is most visible with the transparent menu bar of macOS 26 and later.

## Project layout

```
Sources/MenoCore   Platform-independent logic: models, settings, rules, planning, matching
Sources/Meno       The app: status items, scanning, reveal logic, glass UI, settings
Tests              Unit tests for MenoCore (run on macOS and Linux)
Resources          Info.plist, app icon, localizations
scripts            App bundling, icon generation, localization check
```

## Development

- `swift test` runs the MenoCore tests (they also run on Linux).
- `scripts/check-localization.py` lists user-facing strings and checks the translations in `Resources/*.lproj`.
- `scripts/generate-icon.py` renders `Resources/AppIcon.icns` (needs Pillow and numpy).

## License

Copyright © 2026 whrss9527

Meno is free software, released under the [GNU General Public License v3.0](LICENSE). You may use, study, change and share it. If you distribute Meno or a modified version, you must make its source code available under the same license.

The name "Meno" and the Meno icon are not licensed under the GPL (section 7(e)). You may use them to refer to Meno and when sharing unmodified copies, but a modified version you distribute needs its own name and icon.

Contributions are accepted under the contributor license agreement in [CONTRIBUTING.md](CONTRIBUTING.md).

Meno 0.1.0 was released under the MIT License, and that version stays available under it.
