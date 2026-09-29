import XCTest
@testable import MenoCore

final class AppVersionTests: XCTestCase {
    func testParsing() {
        XCTAssertEqual(AppVersion("0.2.1")?.components, [0, 2, 1])
        XCTAssertEqual(AppVersion("v1.10")?.components, [1, 10])
        XCTAssertEqual(AppVersion(" V2.0.0-beta.1 ")?.components, [2, 0, 0])
        XCTAssertEqual(AppVersion("3.1+build.7")?.description, "3.1")
        XCTAssertNil(AppVersion(""))
        XCTAssertNil(AppVersion("latest"))
        XCTAssertNil(AppVersion("1..2"))
        XCTAssertNil(AppVersion("1.-2"))
    }

    func testOrdering() throws {
        let versions = ["0.1.4", "0.2.0", "0.2.1", "0.10.0", "1.0"].compactMap(AppVersion.init)
        XCTAssertEqual(versions, versions.sorted())
        XCTAssertLessThan(try XCTUnwrap(AppVersion("0.9.9")), try XCTUnwrap(AppVersion("0.10")))
        XCTAssertEqual(AppVersion("1.2"), AppVersion("v1.2.0"))
        XCTAssertFalse(try XCTUnwrap(AppVersion("0.2.0")) < XCTUnwrap(AppVersion("0.2")))
    }
}
