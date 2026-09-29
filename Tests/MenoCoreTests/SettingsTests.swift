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
        // Settings from before keeping sections existed keep them.
        XCTAssertTrue(settings.general.keepsSections)
        XCTAssertEqual(settings.appearance, AppearanceSettings())
    }

    func testCustomIconStates() {
        let known: Set<String> = ["star", "star.fill", "hare", "tortoise.fill"]
        let exists = { known.contains($0) }
        XCTAssertTrue(MenoIcon.customSymbolNames(for: "star", exists: exists) == ("star", "star.fill"))
        // A filled symbol still gets its outline while items are hidden.
        XCTAssertTrue(MenoIcon.customSymbolNames(for: " star.fill ", exists: exists) == ("star", "star.fill"))
        // Without a filled variant, both states look the same.
        XCTAssertTrue(MenoIcon.customSymbolNames(for: "hare", exists: exists) == ("hare", "hare"))
        // Without an outline, the filled symbol stays.
        XCTAssertTrue(MenoIcon.customSymbolNames(for: "tortoise.fill", exists: exists) == ("tortoise.fill", "tortoise.fill"))
        XCTAssertEqual(AppearanceSettings().customIconSymbol, "star")
        XCTAssertNil(MenoIcon.custom.symbolNames)
    }

    func testItemSymbolsRoundTrip() throws {
        XCTAssertEqual(try MenoSettings.decode(from: Data("{}".utf8)).itemSymbols, [:])
        var settings = MenoSettings()
        settings.itemSymbols = ["com.example.sync#solo": "cloud"]
        XCTAssertEqual(try MenoSettings.decode(from: settings.encoded()).itemSymbols, settings.itemSymbols)
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

    func testRulesFromNewerVersionsAreSkipped() throws {
        var settings = MenoSettings()
        settings.rules = [
            AutomationRule(name: "Known", conditions: [.onBattery], action: .zen),
            AutomationRule(name: "Also known", conditions: [.offline], action: .revealHidden),
        ]
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: settings.encoded()) as? [String: Any])
        var rules = try XCTUnwrap(object["rules"] as? [[String: Any]])
        // A rule with a condition this version does not know.
        var future = rules[0]
        future["name"] = "Future"
        future["conditions"] = [["someFutureCondition": [:] as [String: Any]]]
        rules.insert(future, at: 1)
        object["rules"] = rules
        let data = try JSONSerialization.data(withJSONObject: object)

        let decoded = try MenoSettings.decode(from: data)
        XCTAssertEqual(decoded.rules.map(\.name), ["Known", "Also known"])
        XCTAssertEqual(decoded.onboardingCompleted, settings.onboardingCompleted)
    }

    func testLossyArraysKeepTheirShape() throws {
        var settings = MenoSettings()
        settings.rules = [AutomationRule(name: "Known", conditions: [.onBattery], action: .zen)]
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: settings.encoded()) as? [String: Any])
        XCTAssertEqual((object["rules"] as? [Any])?.count, 1)
        XCTAssertEqual((object["markers"] as? [Any])?.count, 0)
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
        for icon in MenoIcon.allCases where icon != .meno && icon != .custom {
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

    func testRevealDefaultsForOlderSettings() throws {
        // Settings saved before these options existed get their defaults.
        let old = #"{"reveal":{"onHover":true,"hoverDelay":0.5}}"#
        let settings = try MenoSettings.decode(from: Data(old.utf8))
        XCTAssertTrue(settings.reveal.onHover)
        XCTAssertEqual(settings.reveal.hoverDelay, 0.5)
        XCTAssertEqual(settings.reveal.hoverModifier, .none)
        XCTAssertTrue(settings.reveal.onDrag)

        var changed = MenoSettings()
        changed.reveal.hoverModifier = .option
        changed.reveal.onDrag = false
        let decoded = try MenoSettings.decode(from: changed.encoded())
        XCTAssertEqual(decoded.reveal.hoverModifier, .option)
        XCTAssertFalse(decoded.reveal.onDrag)
    }

    func testHoverModifier() {
        XCTAssertTrue(HoverModifier.none.isHeld(in: []))
        XCTAssertFalse(HoverModifier.option.isHeld(in: []))
        XCTAssertTrue(HoverModifier.option.isHeld(in: [.option, .shift]))
        XCTAssertFalse(HoverModifier.command.isHeld(in: [.option]))
        XCTAssertTrue(HoverModifier.control.isHeld(in: .control))
    }

    func testGlobalShortcutValidity() {
        XCTAssertNil(KeyCombo(keyCode: 0x00, modifiers: .command).problem(osMajorVersion: 26))
        XCTAssertEqual(KeyCombo(keyCode: 0x00, modifiers: []).problem(osMajorVersion: 26), .needsModifier)
        XCTAssertEqual(KeyCombo(keyCode: 0x00, modifiers: .shift).problem(osMajorVersion: 26), .needsModifier)
        XCTAssertNil(KeyCombo(keyCode: 0x7A, modifiers: []).problem(osMajorVersion: 26))
        // ⌥ or ⌥⇧ alone works up to macOS 14 only.
        let optionSpace = KeyCombo(keyCode: 0x31, modifiers: .option)
        XCTAssertNil(optionSpace.problem(osMajorVersion: 14))
        XCTAssertEqual(optionSpace.problem(osMajorVersion: 15), .needsCommandOrControl)
        XCTAssertEqual(KeyCombo(keyCode: 0x31, modifiers: [.option, .shift]).problem(osMajorVersion: 26), .needsCommandOrControl)
        XCTAssertNil(KeyCombo(keyCode: 0x31, modifiers: [.option, .control]).problem(osMajorVersion: 26))
        XCTAssertNil(KeyCombo(keyCode: 0x31, modifiers: [.option, .command]).problem(osMajorVersion: 27))
    }

    func testSceneShortcuts() throws {
        var settings = MenoSettings()
        let combo = KeyCombo(keyCode: 0x0D, modifiers: [.control, .option])
        settings.scenes = [LayoutScene(name: "Work", layout: SceneLayout(), hotkey: combo)]
        XCTAssertTrue(settings.hotkeyConflicts.isEmpty)
        settings.groups = [ItemGroup(name: "Tools", hotkey: combo)]
        XCTAssertEqual(settings.hotkeyConflicts, [combo])

        // Scenes saved before scene shortcuts decode without one.
        let decoded = try MenoSettings.decode(from: settings.encoded())
        XCTAssertEqual(decoded.scenes.first?.hotkey, combo)
        var json = try XCTUnwrap(String(data: settings.encoded(), encoding: .utf8))
        json = json.replacingOccurrences(of: #""hotkey""#, with: #""oldKey""#)
        let older = try MenoSettings.decode(from: Data(json.utf8))
        XCTAssertEqual(older.scenes.map(\.name), ["Work"])
        XCTAssertNil(older.scenes.first?.hotkey)
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

final class TintTests: XCTestCase {
    func testDarkModeColors() throws {
        var tint = MenuBarTint()
        XCTAssertEqual(tint.colors(dark: true).primary, tint.color)
        tint.usesDarkColors = true
        XCTAssertEqual(tint.colors(dark: true).primary, tint.darkColor)
        XCTAssertEqual(tint.colors(dark: true).secondary, tint.darkSecondaryColor)
        XCTAssertEqual(tint.colors(dark: false).primary, tint.color)

        // Files from before the option keep their look.
        let decoded = try MenoSettings.decode(from: Data(#"{"tint": {"enabled": true}}"#.utf8))
        XCTAssertFalse(decoded.tint.usesDarkColors)
    }
}
