import XCTest
@testable import MenoCore

final class LinkCommandTests: XCTestCase {
    private func command(_ string: String) -> LinkCommand? {
        URL(string: string).flatMap(LinkCommand.init(url:))
    }

    func testShowingAndHiding() {
        XCTAssertEqual(command("meno://show"), .show(all: false))
        XCTAssertEqual(command("meno://show/all"), .show(all: true))
        XCTAssertEqual(command("meno://reveal?all"), .show(all: true))
        XCTAssertEqual(command("meno://hide"), .hide)
        XCTAssertEqual(command("meno://toggle"), .toggle(all: false))
        XCTAssertEqual(command("MENO://Toggle?all=1"), .toggle(all: true))
    }

    func testZen() {
        XCTAssertEqual(command("meno://zen"), .zen(nil))
        XCTAssertEqual(command("meno://zen/on"), .zen(true))
        XCTAssertEqual(command("meno://zen/OFF"), .zen(false))
        XCTAssertNil(command("meno://zen/maybe"))
    }

    func testScenes() {
        XCTAssertEqual(command("meno://scene/Work"), .scene(name: "Work"))
        XCTAssertEqual(command("meno://scene/At%20Home"), .scene(name: "At Home"))
        XCTAssertEqual(command("meno://scene/%E5%B7%A5%E4%BD%9C"), .scene(name: "工作"))
        XCTAssertEqual(command("meno://scene?name=Presenting"), .scene(name: "Presenting"))
        XCTAssertNil(command("meno://scene"))
    }

    func testOpeningItems() {
        XCTAssertEqual(command("meno://open/Wi-Fi"), .open(name: "Wi-Fi", secondary: false))
        XCTAssertEqual(command("meno://open/Dropbox?menu=secondary"), .open(name: "Dropbox", secondary: true))
        XCTAssertEqual(
            command("meno://open?key=com.apple.controlcenter%23id:com.apple.menuextra.wifi"),
            .open(name: "com.apple.controlcenter#id:com.apple.menuextra.wifi", secondary: false)
        )
        XCTAssertNil(command("meno://open"))
    }

    func testPanels() {
        XCTAssertEqual(command("meno://quick-open"), .quickOpen)
        XCTAssertEqual(command("meno://shelf"), .shelf)
        XCTAssertEqual(command("meno://settings"), .settings(pane: nil))
        XCTAssertEqual(command("meno://settings/Rules"), .settings(pane: "rules"))
    }

    func testLinksRoundTrip() {
        let commands: [LinkCommand] = [
            .show(all: false), .show(all: true), .hide, .toggle(all: true), .zen(nil), .zen(true), .zen(false),
            .scene(name: "At Home"), .scene(name: "工作/周末"), .scene(name: "What? #1"),
            .open(name: "com.apple.controlcenter#id:com.apple.menuextra.wifi", secondary: false),
            .open(name: "Dropbox", secondary: true),
            .quickOpen, .shelf, .settings(pane: nil), .settings(pane: "rules"),
        ]
        for command in commands {
            let url = command.url
            XCTAssertNotNil(url, "\(command)")
            XCTAssertEqual(url.flatMap(LinkCommand.init(url:)), command, url?.absoluteString ?? "")
        }
        XCTAssertEqual(LinkCommand.scene(name: "At Home").url?.absoluteString, "meno://scene/At%20Home")
    }

    func testOtherLinks() {
        XCTAssertNil(command("https://example.com/zen"))
        XCTAssertNil(command("meno://unknown"))
    }
}
