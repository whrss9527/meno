import XCTest
@testable import MenoCore

final class MenuItemKeyTests: XCTestCase {
    func testRawValueRoundTrip() {
        let key = MenuItemKey(owner: "com.example.app", token: "id:status#1")
        XCTAssertEqual(key.rawValue, "com.example.app#id:status#1")
        XCTAssertEqual(MenuItemKey(rawValue: key.rawValue), key)
    }

    func testInvalidRawValues() {
        XCTAssertNil(MenuItemKey(rawValue: "no-separator"))
        XCTAssertNil(MenuItemKey(rawValue: "#token"))
        XCTAssertNil(MenuItemKey(rawValue: "owner#"))
    }

    func testCodableAsString() throws {
        let key = MenuItemKey(owner: "com.apple.controlcenter", token: "id:com.apple.menuextra.wifi")
        let data = try JSONEncoder().encode([key])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"["com.apple.controlcenter#id:com.apple.menuextra.wifi"]"#)
        XCTAssertEqual(try JSONDecoder().decode([MenuItemKey].self, from: data), [key])
    }

    func testTokensPreferIdentifiers() {
        let tokens = MenuItemKey.tokens(for: [
            .init(identifier: "com.apple.menuextra.battery", description: "Battery 80%"),
            .init(identifier: "  ", description: "Wi‑Fi"),
        ])
        XCTAssertEqual(tokens, ["id:com.apple.menuextra.battery", "ax:wi fi"])
    }

    func testSingleItemIsSolo() {
        XCTAssertEqual(MenuItemKey.tokens(for: [.init(description: "CPU 42%")]), ["solo"])
    }

    func testDescriptionsAreNormalizedAndDeduplicated() {
        let tokens = MenuItemKey.tokens(for: [
            .init(description: "CPU 12%"),
            .init(description: "CPU 57%"),
            .init(title: "Memory: 8 GB"),
            .init(),
        ])
        XCTAssertEqual(tokens, ["ax:cpu", "ax:cpu~2", "ax:memory gb", "idx:3"])
    }

    func testNormalizeKeepsNonLatinLetters() {
        XCTAssertEqual(MenuItemKey.normalize("  微信 · 3 条新消息 "), "微信 条新消息")
        XCTAssertEqual(MenuItemKey.normalize("123 %"), "")
    }
}
