import XCTest
@testable import MenoCore

final class ItemGroupTests: XCTestCase {
    private let sync = MenuItemKey(owner: "com.example.sync", token: "solo")
    private let vpn = MenuItemKey(owner: "com.example.vpn", token: "solo")

    func testAnItemBelongsToOneGroup() {
        let tools = ItemGroup(name: "Tools")
        let network = ItemGroup(name: "Network", symbol: "network")
        var groups = [tools, network]
        groups.add(sync, to: tools.id)
        groups.add(vpn, to: tools.id)
        XCTAssertEqual(groups.group(containing: vpn)?.id, tools.id)

        groups.add(vpn, to: network.id)
        XCTAssertEqual(groups[0].items, [sync])
        XCTAssertEqual(groups[1].items, [vpn])

        groups.remove(sync)
        XCTAssertNil(groups.group(containing: sync))
        XCTAssertEqual(groups[0].items, [])
    }

    func testAddingToAMissingGroupChangesNothing() {
        var groups = [ItemGroup(name: "Tools", items: [sync])]
        groups.add(sync, to: UUID())
        XCTAssertEqual(groups[0].items, [sync])
    }

    func testGroupsSurviveSaving() throws {
        var settings = MenoSettings()
        settings.groups = [ItemGroup(name: "Tools", symbol: "hammer", items: [sync, vpn])]
        let decoded = try MenoSettings.decode(from: settings.encoded())
        XCTAssertEqual(decoded.groups, settings.groups)
        XCTAssertEqual(try MenoSettings.decode(from: Data("{}".utf8)).groups, [])
    }
}
