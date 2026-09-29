import XCTest
@testable import MenoCore

final class FuzzyMatcherTests: XCTestCase {
    func testEmptyQueryMatchesEverything() {
        XCTAssertEqual(FuzzyMatcher.score("", in: "Anything"), 0)
        XCTAssertEqual(FuzzyMatcher.score("   ", in: "Anything"), 0)
    }

    func testRankingOrder() throws {
        let exact = try XCTUnwrap(FuzzyMatcher.score("wifi", in: "Wi Fi"))
        let prefix = try XCTUnwrap(FuzzyMatcher.score("drop", in: "Dropbox"))
        let wordStart = try XCTUnwrap(FuzzyMatcher.score("center", in: "Control Center"))
        let inner = try XCTUnwrap(FuzzyMatcher.score("box", in: "Dropbox"))
        let subsequence = try XCTUnwrap(FuzzyMatcher.score("ctc", in: "Control Center"))
        XCTAssertGreaterThan(exact, prefix)
        XCTAssertGreaterThan(prefix, wordStart)
        XCTAssertGreaterThan(wordStart, inner)
        XCTAssertGreaterThan(inner, subsequence)
    }

    func testNoMatch() {
        XCTAssertNil(FuzzyMatcher.score("xyz", in: "Dropbox"))
        XCTAssertNil(FuzzyMatcher.score("toolongquery", in: "short"))
    }

    func testInsensitivity() {
        XCTAssertNotNil(FuzzyMatcher.score("CAFE", in: "Café Menu"))
        XCTAssertNotNil(FuzzyMatcher.score("ｗｉｆｉ", in: "WiFi"))
    }

    func testNonLatinText() {
        XCTAssertNotNil(FuzzyMatcher.score("微信", in: "微信"))
        XCTAssertNotNil(FuzzyMatcher.score("网易", in: "网易云音乐"))
    }

    func testInitials() {
        XCTAssertEqual(FuzzyMatcher.initials(of: "Control Center"), "cc")
        XCTAssertEqual(FuzzyMatcher.initials(of: "wei xin"), "wx")
        XCTAssertEqual(FuzzyMatcher.initials(of: "  1Password-Mini "), "1m")
    }

    func testBestScore() {
        XCTAssertEqual(FuzzyMatcher.bestScore("wx", fields: ["微信", "wei xin", "wx"]), 1_000)
        XCTAssertNil(FuzzyMatcher.bestScore("zz", fields: ["a", "b"]))
    }
}
