import XCTest
@testable import MenoCore

final class SettingsTests: XCTestCase {
    func testDefaultsRoundTrip() throws {
        let settings = MenoSettings()
        let decoded = try MenoSettings.decode(from: settings.encoded())
        XCTAssertEqual(decoded, settings)
    }

    func testMissingKeysFallBackToDefaults() throws {
        let json = #"{"reveal": {"onHover": true}, "general": {"stashEnabled": false}}"#
        let settings = try MenoSettings.decode(from: Data(json.utf8))
        XCTAssertTrue(settings.reveal.onHover)
        XCTAssertEqual(settings.reveal.rehideDelay, RevealSettings().rehideDelay)
        XCTAssertFalse(settings.general.stashEnabled)
        XCTAssertEqual(settings.general.revealStyle, .automatic)
        XCTAssertEqual(settings.appearance, AppearanceSettings())
    }

    func testItemNamesRoundTrip() throws {
        XCTAssertEqual(try MenoSettings.decode(from: Data("{}".utf8)).itemNames, [:])
        var settings = MenoSettings()
        settings.itemNames = ["com.apple.controlcenter#id:com.apple.menuextra.focusmode": "Focus", "com.example.sync#solo": "同步"]
        let decoded = try MenoSettings.decode(from: settings.encoded())
        XCTAssertEqual(decoded.itemNames, settings.itemNames)
    }

    func testRevealingWithoutTheIcon() {
        var settings = MenoSettings()
        XCTAssertTrue(settings.appearance.showsMenoIcon)
        XCTAssertTrue(settings.canRevealWithoutIcon)
        settings.reveal.onEmptyAreaClick = false
        XCTAssertFalse(settings.canRevealWithoutIcon)
        settings.hotkeys[.toggleHidden] = KeyCombo(keyCode: 4, modifiers: [.command, .option])
        XCTAssertTrue(settings.canRevealWithoutIcon)
    }

    func testUnknownKeysAreIgnored() throws {
        let json = #"{"futureFeature": {"x": 1}, "shelf": {"iconSize": 22, "brandNew": true}}"#
        let settings = try MenoSettings.decode(from: Data(json.utf8))
        XCTAssertEqual(settings.shelf.iconSize, 22)
    }

    func testRichSettingsRoundTrip() throws {
        var settings = MenoSettings()
        let wifi = MenuItemKey(owner: "com.apple.controlcenter", token: "id:wifi")
        let scene = LayoutScene(name: "Work", layout: SceneLayout(visible: [wifi]), createdAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 200))
        settings.scenes = [scene]
        settings.rules = [
            AutomationRule(name: "Present", conditions: [.appFrontmost(bundleID: "com.apple.Keynote")], action: .zen),
            AutomationRule(name: "Desk", conditions: [.externalDisplay, .timeWindow(startMinute: 540, endMinute: 1080)], action: .applyScene(id: scene.id)),
            AutomationRule(name: "Battery", conditions: [.batteryBelow(percent: 20)], action: .showItem(key: wifi), revertsWhenInactive: false),
        ]
        settings.hotkeys[.quickOpen] = KeyCombo(keyCode: 0x2E, modifiers: [.control, .option])
        settings.itemHotkeys = [ItemHotkey(itemKey: wifi, combo: KeyCombo(keyCode: 0x0D, modifiers: [.command, .option]), click: .secondary)]
        settings.markers = [MenuMarker(kind: .text, text: "Work"), MenuMarker(kind: .space, width: 24)]
        settings.spacing.spacing = 6
        settings.shelf.tint = RGBAColor(red: 1, green: 0.5, blue: 0, alpha: 0.2)
        settings.tint.enabled = true
        settings.tint.shape = .split

        let decoded = try MenoSettings.decode(from: settings.encoded())
        XCTAssertEqual(decoded, settings)
    }

    func testStoredNilOptionalsStayNil() throws {
        var settings = MenoSettings()
        settings.spacing.spacing = nil
        settings.shelf.tint = nil
        let decoded = try MenoSettings.decode(from: settings.encoded())
        XCTAssertNil(decoded.spacing.spacing)
        XCTAssertNil(decoded.shelf.tint)
    }

    func testEnumCaseReplacementIsNotMerged() {
        let base: [String: Any] = ["action": ["revealHidden": [String: Any]()]]
        let stored: [String: Any] = ["action": ["applyScene": ["id": "X"]]]
        let merged = TolerantJSON.merge(base, stored) as? [String: Any]
        let action = merged?["action"] as? [String: Any]
        XCTAssertEqual(action?.keys.sorted(), ["applyScene"])
    }

    func testHidingEngineResolution() {
        XCTAssertEqual(HidingEngine.automatic.resolved(osMajorVersion: 26), .wide)
        XCTAssertEqual(HidingEngine.automatic.resolved(osMajorVersion: 27), .stepped)
        XCTAssertEqual(HidingEngine.wide.resolved(osMajorVersion: 27), .wide)
        XCTAssertEqual(HidingEngine.stepped.resolved(osMajorVersion: 14), .stepped)
    }

    func testMenoIconSymbols() {
        XCTAssertNil(MenoIcon.meno.symbolNames)
        for icon in MenoIcon.allCases where icon != .meno {
            XCTAssertNotNil(icon.symbolNames, "\(icon)")
        }
    }
}

final class KeyComboTests: XCTestCase {
    func testCarbonFlags() {
        XCTAssertEqual(KeyModifiers.command.carbonFlags, 0x100)
        XCTAssertEqual(KeyModifiers.shift.carbonFlags, 0x200)
        XCTAssertEqual(KeyModifiers.option.carbonFlags, 0x800)
        XCTAssertEqual(KeyModifiers.control.carbonFlags, 0x1000)
        XCTAssertEqual(KeyModifiers([.command, .option]).carbonFlags, 0x900)
    }

    func testDisplayString() {
        let combo = KeyCombo(keyCode: 0x2E, modifiers: [.command, .control, .option, .shift])
        XCTAssertEqual(combo.displayString(), "⌃⌥⇧⌘M")
        XCTAssertEqual(KeyCombo(keyCode: 0x31, modifiers: .option).displayString(), "⌥Space")
        XCTAssertEqual(KeyCombo(keyCode: 0x2E, modifiers: .command).displayString(keyName: "Ь"), "⌘Ь")
    }

    func testGlobalShortcutValidity() {
        XCTAssertTrue(KeyCombo(keyCode: 0x00, modifiers: .command).isValidGlobalShortcut)
        XCTAssertFalse(KeyCombo(keyCode: 0x00, modifiers: []).isValidGlobalShortcut)
        XCTAssertFalse(KeyCombo(keyCode: 0x00, modifiers: .shift).isValidGlobalShortcut)
        XCTAssertTrue(KeyCombo(keyCode: 0x7A, modifiers: []).isValidGlobalShortcut)
    }

    func testConflicts() {
        var bindings = HotkeyBindings()
        let combo = KeyCombo(keyCode: 0x01, modifiers: [.control, .option])
        bindings[.quickOpen] = combo
        bindings[.toggleZen] = KeyCombo(keyCode: 0x02, modifiers: [.control, .option])
        let item = ItemHotkey(itemKey: MenuItemKey(owner: "a", token: "solo"), combo: combo)
        XCTAssertEqual(bindings.conflicts(with: [item]), [combo])
        XCTAssertTrue(bindings.conflicts(with: []).isEmpty)
    }
}
