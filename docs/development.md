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

- `swift test` runs the MenoCore tests. CI runs them on Linux with Swift 5.10 as well as on both macOS runners. Inventory building, reveal counters and divider repair decisions are pure core logic; Accessibility payloads, timers and system effects stay in the app.
- `scripts/check-secure-input.sh` tests waiting and cancellation with real Secure Keyboard Entry, then measures the production window and pointer drag paths on two disposable helper items. It needs Accessibility and a test Mac without another secure-input holder; CI runs it on macOS 15 and 26.
- `scripts/check-localization.py` lists user-facing strings and checks the translations in `Resources/*.lproj`.
- `scripts/generate-icon.py` renders `Resources/AppIcon.icns` (needs Pillow and numpy).
- `scripts/measure-footprint.sh` measures what the built app costs while idle, as set up and with 20 other apps' items, hover and a rule, and fails above its limits, `scripts/check-hiding.sh` checks with a menu bar item of its own that hiding and showing work, and that a Hidden divider right of the Meno icon is put back on its left, and `scripts/check-moving.sh` that Meno moves an item of its own by its window, to Visible and back. CI runs all three on macOS 15 and 26, and a run started by hand can add another runner, such as a new macOS, with the *runner* input; they need a Mac where Meno has not been set up, and Accessibility for the app that runs them. With `MENO_DIAG=1` in its environment Meno prints its scans and its diagnostic report to standard error, and the report again on `SIGUSR1`.

### Releases

New versions are published by pushing a `v*` tag or by running the *Release* workflow with a version number. The workflow uses the shared release workflow in [Frit](https://github.com/whrss9527/frit): with the Developer ID secrets set (see Frit's [docs/release.md](https://github.com/whrss9527/frit/blob/main/docs/release.md)) it signs, notarizes and staples the app. The notes come from `.github/releases/<tag>.md`.

Periodic catch-up scans on macOS 26 and earlier reuse completed scans only when status-window IDs, owners and bounds are unchanged. Explicit refreshes still scan, and macOS 27 keeps its existing behavior. Diagnostic scan lines distinguish `mode=full` from `mode=skipped`. The footprint summary includes skipped-check percentage and CPU across surviving processes; background runner activity affects this measurement. Manually dispatch CI with `compare_scans` to measure both disabled and enabled gating, or set `MENO_SCAN_GATE=0` for a local baseline.
