import XCTest
@testable import MenoCore

final class ItemGroupTests: XCTestCase {
    private let sync = MenuItemKey(owner: "com.example.sync", token: "solo")
    private let backup = MenuItemKey(owner: "com.example.backup", token: "solo")

    func testAnItemBelongsToOneGroup() {
        let tools = ItemGroup(name: "Tools")
        let network = ItemGroup(name: "Network", symbol: "network")
        var groups = [tools, network]
        groups.add(sync, to: tools.id)
        groups.add(backup, to: tools.id)
        XCTAssertEqual(groups.group(containing: backup)?.id, tools.id)

        groups.add(backup, to: network.id)
        XCTAssertEqual(groups[0].items, [sync])
        XCTAssertEqual(groups[1].items, [backup])

        groups.remove(sync)
        XCTAssertNil(groups.group(containing: sync))
        XCTAssertEqual(groups[0].items, [])
    }

    func testAddingToAMissingGroupChangesNothing() {
        var groups = [ItemGroup(name: "Tools", items: [sync])]
        groups.add(sync, to: UUID())
        XCTAssertEqual(groups[0].items, [sync])
    }

    func testGroupShortcutsCountAsConflicts() {
        let combo = KeyCombo(keyCode: 5, modifiers: [.command, .option])
        var bindings = HotkeyBindings()
        bindings[.quickOpen] = combo
        XCTAssertEqual(bindings.conflicts(with: [], groupHotkeys: [combo]), [combo])
        XCTAssertTrue(bindings.conflicts(with: [], groupHotkeys: []).isEmpty)
    }

    func testGroupsFromBeforeShortcutsStillLoad() throws {
        let json = #"{"groups": [{"id": "5B0F7F7E-8E6C-4B0E-9C57-3A1D1D6C2E11", "name": "Tools", "symbol": "hammer", "items": []}]}"#
        let settings = try MenoSettings.decode(from: Data(json.utf8))
        XCTAssertEqual(settings.groups.map(\.name), ["Tools"])
        XCTAssertNil(settings.groups.first?.hotkey)
    }

    func testGroupsSurviveSaving() throws {
        var settings = MenoSettings()
        settings.groups = [ItemGroup(name: "Tools", symbol: "hammer", items: [sync, backup], hotkey: KeyCombo(keyCode: 17, modifiers: [.control, .option]))]
        let decoded = try MenoSettings.decode(from: settings.encoded())
        XCTAssertEqual(decoded.groups, settings.groups)
        XCTAssertEqual(try MenoSettings.decode(from: Data("{}".utf8)).groups, [])
    }
}
