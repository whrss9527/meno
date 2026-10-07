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

### Distribution and App Sandbox

Meno ships through Developer ID signing and Apple notarization. There is no Mac App Store edition: preserving the current full feature set is incompatible with a sandboxed build. Apple's [review guidelines §2.4.5](https://developer.apple.com/app-store/review/guidelines/#hardware-compatibility) require Mac App Store apps to be sandboxed and use the store for updates; [App Sandbox documentation](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox) describes its restrictions.

The current implementation relies on:

- Reading other apps' Accessibility trees in `MenuBarScanner.swift` and `AX.swift`.
- Posting synthetic clicks and drags to other processes in `EventSynthesizer.swift`.
- Looking up `CGWindowListCreateImage` with `dlsym` in `WindowCapture.swift` to capture off-screen windows. This is an unavailable former public API, not a private symbol.
- Running `tccutil` to reset Accessibility authorization in `PermissionCenter.swift`.
- Writing current-host global preferences and terminating or relaunching other processes in `SpacingController.swift`.
- Replacing its own installed app bundle in `UpdateInstaller.swift`.

These are current implementation dependencies, not a claim that every API listed is categorically private or forbidden in every sandboxed app. A store edition would require a separate reduced product and update path; adding a sandbox entitlement to this target does not preserve Meno's behavior.

### Strict concurrency

The package requires Swift 6 (Xcode 16 or later). `MenoCore` uses Swift 6 language mode; the app and tests retain Swift 5 mode. `scripts/check-concurrency.sh` builds in a fresh temporary directory with complete concurrency checking, so cached builds cannot hide warnings. CI records the core and app warning counts in its job summary.

The core must have zero warnings. The app baseline in `scripts/concurrency-baseline.json` records ten existing diagnostics at nine source locations, measured with Swift 6.3.3 / Xcode 26.6. Toolchains may report fewer; new locations, additional diagnostics at an existing location, or a larger total fail CI. Fixing warnings can reduce the baseline. When moving source lines, review the diagnostics before updating their recorded locations; do not raise the budget to make a change pass.

### Settings compatibility

`settings.json` writes `schemaVersion: 1`; files without a version use the same schema. Add keys with defaults, keep existing names and types, and avoid repurposing values. A breaking schema needs an explicit migration and a backup before replacement.

When a file has a higher schema version, Settings shows a notice. Meno reads supported values, retains the higher version number, and writes unrecognized keys back, including nested fields and fields attached to records by identity. Records that cannot be decoded remain inert and are retained in their original positions. Editing supported values takes precedence; deleting a recognized record or a name still deletes it. Existing fallback handling for unsupported values in recognized enum fields remains unchanged. Import, export, backups, delayed saves and quit-time flushes all use `MenoSettings.decode(from:)` / `encoded()`; use these entry points rather than encoding the model directly.

### Project layout

```
Sources/MenoCore   Platform-independent logic: models, settings, rules, planning, matching
Sources/Meno       The app: status items, scanning, reveal logic, glass UI, settings
Tests              Unit tests for MenoCore (run on macOS and Linux)
Resources          Info.plist, app icon, localizations
scripts            App bundling, icon generation, localization check
```

### Tests and scripts

- `scripts/check-single-instance.sh` starts two disposable bundles with the production single-instance arbitration. Both wait at a shared launch barrier, then exactly the lower-PID copy must survive after three seconds, repeated three times. It does not start menu-bar controllers or change user settings. CI runs it on both macOS versions.
- `scripts/check-updating.sh` compiles a test entry point with the production updater and toast UI. Disposable ad hoc bundles and a unique preferences domain verify 0.0.1 → 0.0.2 installation, download cleanup, early-exit rollback and its visible notice, without starting menu-bar controllers or changing Meno settings. CI runs it on main and manual runs. `MENO_UPDATE_URL` can point at loopback release JSON; local archive URLs must use the same origin, and normal installer verification still applies.
- `swift test` runs the MenoCore tests. CI runs them on Linux with Swift 6 as well as on both macOS runners. Linux also checks localizations. Internal branches run once per push; pull requests from forks run the same checks in this repository with read-only permissions. Inventory building, reveal counters and divider repair decisions are pure core logic; Accessibility payloads, timers and system effects stay in the app.
- `scripts/check-secure-input.sh` tests waiting and cancellation with real Secure Keyboard Entry, then measures the production window and pointer drag paths on two disposable helper items. It needs Accessibility and a test Mac without another secure-input holder; CI runs it on macOS 15 and 26.
- `scripts/check-localization.py` lists user-facing strings and checks the translations in `Resources/*.lproj`.
- `scripts/generate-icon.py` renders `Resources/AppIcon.icns` (needs Pillow and numpy).
- `scripts/measure-footprint.sh` measures what the built app costs while idle, as set up and with 20 other apps' items, hover and a rule, and fails above its limits, `scripts/check-hiding.sh` checks with a menu bar item of its own that hiding and showing work, and that a Hidden divider right of the Meno icon is put back on its left, and `scripts/check-moving.sh` that Meno moves an item of its own by its window, to Visible and back. CI runs hiding and moving on macOS 15 and 26 for every checked commit; footprint runs only on main or manual runs. A run started by hand can add another runner, such as a new macOS, with the *runner* input; they need a Mac where Meno has not been set up, and Accessibility for the app that runs them. With `MENO_DIAG=1` in its environment Meno prints its scans and its diagnostic report to standard error, and the report again on `SIGUSR1`.

### Releases

New versions are published by pushing a `v*` tag or by running the *Release* workflow with a version number. The workflow uses the shared release workflow in [Frit](https://github.com/whrss9527/frit): with the Developer ID secrets set (see Frit's [docs/release.md](https://github.com/whrss9527/frit/blob/main/docs/release.md)) it signs, notarizes and staples the app. The notes come from `.github/releases/<tag>.md`.

Periodic catch-up scans on macOS 26 and earlier reuse completed scans only when status-window IDs, owners and bounds are unchanged. Explicit refreshes still scan, and macOS 27 keeps its existing behavior. Diagnostic scan lines distinguish `mode=full` from `mode=skipped`. The footprint summary includes skipped-check percentage and CPU across surviving processes; background runner activity affects this measurement. Manually dispatch CI with `compare_scans` to measure both disabled and enabled gating, or set `MENO_SCAN_GATE=0` for a local baseline.

CI requires a nonempty release notes file for `VERSION`. The release workflow checks the requested version or tag against `VERSION` before building; a mismatch or missing notes stops publication.
