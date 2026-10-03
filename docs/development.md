# Developing Meno

[← Back to the README](../README.md) · [简体中文](development.zh-CN.md)

## Development

Building needs Xcode 16 or later (Xcode 26 for Liquid Glass).

### Build and run

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

### Project layout

```
Sources/MenoCore   Platform-independent logic: models, settings, rules, planning, matching
Sources/Meno       The app: status items, scanning, reveal logic, glass UI, settings
Tests              Unit tests for MenoCore (run on macOS and Linux)
Resources          Info.plist, app icon, localizations
scripts            App bundling, icon generation, localization check
```

### Tests and scripts

- `swift test` runs the MenoCore tests (they also run on Linux).
- `scripts/check-localization.py` lists user-facing strings and checks the translations in `Resources/*.lproj`.
- `scripts/generate-icon.py` renders `Resources/AppIcon.icns` (needs Pillow and numpy).
- `scripts/measure-footprint.sh` measures what the built app costs while idle, `scripts/check-hiding.sh` checks with a menu bar item of its own that hiding and showing work, and that a Hidden divider right of the Meno icon is put back on its left, and `scripts/check-moving.sh` that an item the pointer cannot reach still moves. CI runs all three on macOS 15 and 26; they need a Mac where Meno has not been set up, and Accessibility for the app that runs them. With `MENO_DIAG=1` in its environment Meno prints its scans and its diagnostic report to standard error, and the report again on `SIGUSR1`. With `MENO_MOVE_BY_WINDOW=1` it moves every item by its window, as it otherwise only does for items the pointer cannot reach.

### Releases

New versions are published by pushing a `v*` tag or by running the *Release* workflow with a version number. The workflow uses the shared release workflow in [Frit](https://github.com/whrss9527/frit): with the Developer ID secrets set (see Frit's [docs/release.md](https://github.com/whrss9527/frit/blob/main/docs/release.md)) it signs, notarizes and staples the app. The notes come from `.github/releases/<tag>.md`.
