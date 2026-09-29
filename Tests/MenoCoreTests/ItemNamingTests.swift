import XCTest
@testable import MenoCore

final class ItemNamingTests: XCTestCase {
    func testUnnamedSystemElementsAreRecognized() {
        XCTAssertTrue(ItemNaming.isUnnamedSystemElement(owner: "com.apple.controlcenter", texts: [nil, "", "  "]))
        XCTAssertFalse(ItemNaming.isUnnamedSystemElement(owner: "com.apple.controlcenter", texts: ["Wi‑Fi", nil, nil]))
        XCTAssertFalse(ItemNaming.isUnnamedSystemElement(owner: "com.apple.controlcenter", texts: [nil, nil, "Clock"]))
    }

    func testUnnamedItemsOfOtherAppsAreKept() {
        XCTAssertFalse(ItemNaming.isUnnamedSystemElement(owner: "com.example.app", texts: [nil, nil, nil]))
    }

    func testLeadingNameDropsTheState() {
        XCTAssertEqual(ItemNaming.leadingName(of: "Wi‑Fi, connected, 3 bars"), "Wi‑Fi")
        XCTAssertEqual(ItemNaming.leadingName(of: "Wi-Fi，已接入，3格"), "Wi-Fi")
        XCTAssertEqual(ItemNaming.leadingName(of: "控制中心、录屏正被使用"), "控制中心")
    }

    func testLeadingNameKeepsPlainNames() {
        XCTAssertEqual(ItemNaming.leadingName(of: "音频和视频控制"), "音频和视频控制")
        XCTAssertEqual(ItemNaming.leadingName(of: " Clock "), "Clock")
        XCTAssertEqual(ItemNaming.leadingName(of: ", odd"), ", odd")
    }
}
