# Meno guide

[← Back to the README](../README.md) · [简体中文](guide.zh-CN.md)

## Install

Meno runs on macOS 14 Sonoma or later. Liquid Glass needs macOS 26 and a build made with Xcode 26.

Download `Meno.zip` from the [latest release](https://github.com/whrss9527/meno/releases/latest), unzip it and move Meno.app to *Applications*. The app is universal (Apple silicon and Intel). From 0.10.0 on it is signed with a Developer ID and notarized by Apple, so it opens with a double-click. Versions before 0.10.0 are signed ad hoc: right-click Meno.app and choose *Open*, or run `xattr -dr com.apple.quarantine /Applications/Meno.app`.

Meno installs updates itself: when a check finds a newer release, choose *Install and Relaunch* in the notice, in *Settings › About* or in Meno's menu. *Settings › About* also lists what changed in every version since yours, newest first. Meno downloads the release from GitHub, checks its checksum, version and code signature, replaces itself and opens again. When Meno runs from a folder it cannot write to, it offers the download instead.

After an update, macOS may keep an entry for the previous build in the Accessibility list that no longer counts. Meno then opens *Settings › Permissions*, replaces the entry and macOS asks again; *Reset and Grant Again* does the same by hand. Releases from 0.10.0 on are signed with the same Developer ID certificate, so later updates keep the permission; only the update from an ad hoc version asks once more.

## Features

### Hide and reveal

- **Three sections.** *Visible* items are always shown. *Hidden* items appear on demand. The *Stash* is for items you almost never need: they never appear in the menu bar, only in the Shelf, Quick Open or with ⌥-click.
- **Many ways to reveal:** click the Meno icon, click or hover over an empty part of the menu bar (hovering can require a held key), scroll or swipe down over it, press a global shortcut, or drag a file onto the menu bar to drop it on a hidden item.
- **Smart re-hiding:** after a delay, when you switch apps or click elsewhere, or when the pointer leaves the menu bar. Items stay put while one of their menus is open.
- **Room when you need it:** Meno can clear the frontmost app's menus while items are revealed, so a long row of icons fits.
- **Items stay where you put them:** when an app restarts and macOS puts its icon at the left end of the menu bar, in another section, Meno moves it back. When many items moved at once, it asks first.

### Glass interface

- **Shelf:** a Liquid Glass bar below the menu bar that shows hidden items. Useful next to the camera housing, where the menu bar runs out of space. With *Automatic* reveal, Meno picks the Shelf only when items would not fit. Visible items that macOS put behind the camera housing come first, so they can still be clicked. Opened with a hotkey, it works from the keyboard: ← and → or Tab pick an item, as does typing the start of its name, and ↩ opens it. An app's item can also show the app in Finder or quit it, handy for menu bar apps without a Dock icon.
- **Quick Open:** a Spotlight-style palette (fuzzy search, pinyin and initials included) to open any menu bar item from the keyboard, or to run Meno's actions such as applying a scene or turning on Zen. ↩ opens, ⌘↩ opens the secondary menu, ⌥↩ reveals the item in place, ⌘1–⌘9 pick a result. ⌘K or a right-click lists what else can be done with an item: move it to another section, show it for a while, copy its link, or show its app in Finder and quit it.
- **Layout editor:** drag items between the Visible, Hidden and Stash lanes, or next to other items to reorder them. Meno performs the ⌘-drags for you. Items can be renamed and given a symbol of your choice, which helps with items that macOS reports without a useful name or icon. ⌘F finds an item among many, and *Show for a While* keeps a hidden item in the menu bar for 15 minutes to 4 hours before putting it back.
- **Show when it changes:** pick hidden items that Meno shows for a moment when their icon or text changes, for example when a sync fails. Until you look, a dot on the Meno icon, on the icon of the item's group and in the Shelf marks what changed.
- **Groups:** put items that belong together behind one icon of their own. Clicking the icon, or the group's own shortcut, shows the group in a Shelf right below it, and the items stay out of the menu bar.
- Liquid Glass on macOS 26 and later; a frosted-glass look with a light rim on macOS 14 and 15.

### Make it yours

- **Rules:** "When a microphone is in use, turn on Zen." Conditions include the frontmost or running app, a microphone or camera in use, battery, power and Low Power Mode, external or specific displays and the display whose menu bar is in use, the time of day and the day of the week, the network the Mac is on (recognized by its router, without Location Services), being offline and a shell command of your own that succeeds; a rule can need all of its conditions or any one of them. Actions reveal or hide sections, apply a scene, turn on Zen, or move a specific item — and can be undone automatically. Moves wait until you are not using the mouse and keyboard. *Pause Rules* in Meno's menu, or a shortcut of its own, stops them all for a while.
- **Scenes:** save arrangements such as *Work*, *Home* or *Presenting* and switch between them from the menu, with a rule or with a shortcut of their own. Export scenes and rules to a `.meno` file for another Mac or for someone else; opening the file, or dropping it on Settings, shows what it holds before anything is imported.
- **Zen:** one shortcut clears every app icon, leaving only system status. Great for screenshots, recordings and talks.
- **Item shortcuts:** open a specific item (Wi-Fi, Bluetooth, a timer…) from anywhere, even while it is hidden.
- **Links:** `meno://` links let Shortcuts, launchers and scripts show or hide items, switch Zen, apply a scene or open an item. Scenes and items offer *Copy Link*.
- **Markers:** add spaces, thin lines, dots, SF Symbols or short text labels to the menu bar to group your items.
- **Insights:** private, on-device statistics — how often you reveal, your most used items, and suggestions such as "you opened this 12 times this week while it was hidden — keep it visible?" or stashing what you have not used for months. Suggestions you turn down stay away for two months.
- **New arrivals:** when an app adds a new icon, Meno can ask you, hide it or stash it.
- **Appearance:** choose the Meno icon or any SF Symbol for it, divider style, Shelf glass and tint, a menu bar tint in your own colors or the wallpaper's, with gradient, border, shadow and split "island" shapes (experimental), and system-wide icon spacing (beta).
- English, Simplified Chinese and Traditional Chinese. Meno follows the system language, or the one chosen in *Settings › General › Language*.

## Links

| Link | Does |
| --- | --- |
| `meno://show`, `meno://show/all` | Shows the hidden items, or everything including the Stash |
| `meno://hide`, `meno://toggle` | Hides them again, or switches |
| `meno://zen`, `meno://zen/on`, `meno://zen/off` | Switches Zen, turns it on or off |
| `meno://scene/Work` | Applies the scene named *Work* |
| `meno://group/Tools` | Shows the group named *Tools* below its icon |
| `meno://open/Wi-Fi`, `meno://open/Wi-Fi?menu=secondary` | Opens a menu bar item by name |
| `meno://quick-open`, `meno://shelf`, `meno://settings/rules` | Opens Quick Open, the Shelf or a Settings pane |

For example, `open meno://zen/on` in Terminal, or an *Open URLs* action in Shortcuts. For names with spaces or other scripts, *Copy Link* gives a link that is already encoded.

On macOS 26 and later, a Focus can change the menu bar too: in Shortcuts, add an automation for when the Focus turns on, with an *Open URLs* action and a scene's link, such as `meno://scene/Work`, and another for when it turns off.

## How it works

Meno adds small dividers to the menu bar: a single chevron starts the Hidden section, a double chevron the Stash. Everything left of a divider belongs to that section. Hold ⌘ and drag icons across the dividers, or use the Layout editor.

To hide a section, its divider grows until the items to its left no longer fit:

- **Wide engine (macOS 14–26):** one divider grows far past the edge of the screen.
- **Stepped engine (macOS 27):** the macOS 27 menu bar drops items wider than about half of the display, and large length changes do not push neighbours along. Meno grows the divider together with a few helper spacers, each just below that limit, in 40 pt steps. Items pushed out go into the system overflow menu. You can choose the engine in *Settings › General › Advanced*.

Menu bar items are read through each app's accessibility tree, which works on every supported macOS version, including the single-window menu bar of macOS 27.

## Footprint

Left alone, Meno uses about a tenth of a percent of one CPU core and 10 to 15 MB of memory, as Activity Monitor counts it. CI measures this after every change to the main branch: `scripts/measure-footprint.sh` starts the app, leaves it alone for a minute and adds the numbers to the run's summary.

| Idle for a minute, Apple silicon | macOS 26 | macOS 15 |
| --- | --- | --- |
| CPU | 0.13 % of one core | 0.12 % of one core |
| Memory | 14.2 MB | 9.7 MB |
| Wake-ups | 0.1 per second | 0.1 per second |
| A look over the menu bar, usually | 37–49 ms | 34–53 ms |

- Meno hears about most changes as they happen, such as apps starting and quitting, and looks over the whole menu bar only every 20 seconds (every minute in Low Power Mode) to catch what slipped through. It does not look while the displays sleep or another user's session is in front.
- Nothing is captured from the screen in the background.
- Rules that run a command or depend on the network only do that work while such a rule is on.

The measurements run on GitHub's virtual Macs, which have only macOS's own menu bar items; with more items, each look at the menu bar takes a little longer.

## Permissions and privacy

| Permission | Needed for |
| --- | --- |
| **Accessibility** (required) | Reading menu bar items, opening them from the Shelf, Quick Open and shortcuts, and arranging them with ⌘-drag. |
| **Screen Recording** (optional) | Showing the real artwork of hidden items (macOS 14–26), and noticing when their icons change if you turn that on. Without it Meno shows app icons. Only menu bar items are captured, while the Shelf, Quick Open or Settings is open or while icons are compared; macOS shows its recording indicator in the menu bar meanwhile. |

Rules about a microphone or camera in use only ask macOS whether a device is running, which needs no permission. Meno never records anything.

A rule condition that runs a command runs exactly the command you typed, every 10 seconds with zsh, and only while the rule is on. While a rule depends on a network, Meno runs `route` and `arp` when the network changes and every 30 seconds, which read the router of each connection from what macOS already knows and send nothing. Rules with commands are turned off when you import settings, so a settings file cannot run anything before you have looked at it.

Meno has no analytics or accounts. It only goes online to ask GitHub for the latest release and the notes of the versions since yours: when you click *Check for Updates* in *Settings › About*, or once a day if you turn that on in *General*; and to download a release you chose to install. Settings and statistics live in `~/Library/Application Support/Meno`.

## Troubleshooting

- **Meno does not respond after an update.** Builds without a fixed certificate get a new Accessibility entry with every update. Meno replaces the old entry and macOS asks again; if it does not, open *Settings › Permissions* and click *Reset and Grant Again*.
- **An update cannot be installed from within Meno.** Meno replaces itself only where it may write, for example in *Applications* with an administrator account, and not while macOS runs it from a temporary copy of a download. Otherwise it offers the download instead.
- **An app's icon or the Meno icon is missing on macOS 26 or later.** macOS only shows the items of apps that are allowed in *System Settings › Menu Bar*. Meno's own icon can also be turned off in *Settings › Appearance*; open Settings from Quick Open, with `open meno://settings` or by opening Meno again.
- **Icons disappeared after you moved a divider and clicked it.** Everything left of the single-chevron divider belongs to the Hidden section, so moving the divider to the right takes along the icons it passes, and clicking it hides them together with the divider. Click the Meno icon, or the empty part of the menu bar where the divider was, to show them again, then ⌘-drag the divider back or use the Layout pane. A divider dragged to the right of the Meno icon is put back on its left within a few seconds, so that hiding never hides the Meno icon; should it be gone meanwhile, run `open meno://show/all`.
- **An item moves back after you moved it.** Meno only puts an item back when its app, or Meno itself, has just started and the item is not where it was last left while Meno ran. Items you move while Meno runs stay where you put them. To stop this, turn off *Keep items where you put them* in *General › Sections*.
- **macOS asks every month whether Meno may keep recording the screen (macOS 15 to 26).** Screen Recording is optional: without it the Shelf shows app icons instead of the items' own artwork, and changes are noticed by text only.
- **A purple indicator says "Meno is capturing your screen".** macOS shows it whenever Meno captures the artwork of menu bar items: when the Shelf, Quick Open or Settings opens, at most every 30 seconds, and every few seconds while *Compare icons too* is on. Turn off Screen Recording for Meno to stop it; Meno then shows app icons.
- **macOS calls Meno "Meno 2".** There are two copies, for example after a download was kept next to the old one. *Settings › About* shows where the other copy is; keep one. Only one copy runs at a time: opening another shows the running one's Settings, or takes over when it is newer.
- Anything else: *Settings › About › Copy Diagnostic Report* copies what Meno sees, to paste into an issue.

## Good to know

- Moving items simulates ⌘-drags, so Meno briefly takes over the pointer and puts it back afterwards. Items the pointer cannot reach, behind the camera housing or off the screen, are dragged through their own windows instead on macOS 14–26; on macOS 27 they have to fit in the menu bar first. The clock and the Control Center icon cannot be moved.
- Icon spacing uses the `NSStatusItemSpacing` and `NSStatusItemSelectionPadding` preferences, which apps read at launch. Applying it relaunches apps that own menu bar items.
- The menu bar tint is drawn behind the menu bar and is most visible with the transparent menu bar of macOS 26 and later.
- With several displays, every menu bar shows the same items in the same order: macOS keeps them on the menu bar of the display you are using and shows them on the others as well. Meno hides and shows them alike on all displays. For more room on a large display, add the rule *Show hidden items on an external display*, or use the condition *The menu bar is on a specific display*.
