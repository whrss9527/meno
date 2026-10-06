import XCTest
@testable import MenoCore

final class UpdateSourceTests: XCTestCase {
    func testOnlyLoopbackEndpointsAreAccepted() {
        for text in ["http://127.0.0.1:9876/latest.json", "http://localhost/latest", "http://[::1]:9876/latest"] {
            XCTAssertNotNil(UpdateSource(override: text))
        }
        for text in [nil, "https://example.com/latest", "file:///tmp/latest", "http://localhost.example.com/latest", "http://user:pass@localhost/latest"] {
            XCTAssertNil(UpdateSource(override: text))
        }
    }

    func testLocalAssetsMustComeFromSameOriginAndRequireExplicitSource() throws {
        let source = try XCTUnwrap(UpdateSource(override: "http://127.0.0.1:9876/latest.json"))
        let archive = UpdateRelease.Asset(name: "Meno.zip", downloadURL: URL(string: "http://127.0.0.1:9876/Meno.zip")!)
        let release = UpdateRelease(tagName: "v0.0.2", htmlURL: source.latestURL, assets: [archive])
        XCTAssertNil(release.appArchive(repository: "whrss9527/meno"))
        XCTAssertEqual(release.appArchive(repository: "whrss9527/meno", source: source), archive)
        XCTAssertFalse(source.accepts(URL(string: "http://127.0.0.1:9877/Meno.zip")!))
        XCTAssertFalse(source.accepts(URL(string: "http://localhost:9876/Meno.zip")!))
        XCTAssertFalse(source.accepts(URL(string: "https://127.0.0.1:9876/Meno.zip")!))
    }
}
