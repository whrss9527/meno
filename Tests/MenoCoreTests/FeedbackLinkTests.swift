import XCTest
@testable import MenoCore

final class FeedbackLinkTests: XCTestCase {
    func testPrefillsTheIssueTemplateWithBothVersions() {
        let url = FeedbackLink.bugReport(repositoryURL: URL(string: "https://github.com/whrss9527/meno")!,
                                        version: "0.12.10 (123)", systemVersion: "26.5.0")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        XCTAssertEqual(components.path, "/whrss9527/meno/issues/new")
        XCTAssertEqual(components.queryItems, [URLQueryItem(name: "template", value: "bug.yml"),
                                             URLQueryItem(name: "version", value: "Meno 0.12.10 (123); macOS 26.5.0")])
    }

    func testVersionDetailsCannotInjectAnotherQueryField() {
        let url = FeedbackLink.bugReport(repositoryURL: URL(string: "https://github.com/whrss9527/meno")!,
                                        version: "dev&template=other.yml#test", systemVersion: "26.0 + beta")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        XCTAssertNil(components.fragment)
        XCTAssertEqual(components.queryItems?.count, 2)
        XCTAssertEqual(components.queryItems?.last?.value, "Meno dev&template=other.yml#test; macOS 26.0 + beta")
    }
}
