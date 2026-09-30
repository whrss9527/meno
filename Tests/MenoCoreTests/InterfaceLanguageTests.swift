import XCTest
@testable import MenoCore

final class InterfaceLanguageTests: XCTestCase {
    func testStoredValueRoundTrips() {
        for language in InterfaceLanguage.allCases {
            XCTAssertEqual(InterfaceLanguage(appleLanguages: language.appleLanguages), language)
        }
    }

    func testFollowingTheSystemRemovesTheValue() {
        XCTAssertNil(InterfaceLanguage.system.appleLanguages)
        XCTAssertEqual(InterfaceLanguage.english.appleLanguages, ["en"])
        XCTAssertEqual(InterfaceLanguage.simplifiedChinese.appleLanguages, ["zh-Hans"])
        XCTAssertEqual(InterfaceLanguage.traditionalChinese.appleLanguages, ["zh-Hant"])
    }

    func testMissingOrUnexpectedValuesFollowTheSystem() {
        XCTAssertEqual(InterfaceLanguage(appleLanguages: nil), .system)
        XCTAssertEqual(InterfaceLanguage(appleLanguages: [String]()), .system)
        XCTAssertEqual(InterfaceLanguage(appleLanguages: "en"), .system)
        XCTAssertEqual(InterfaceLanguage(appleLanguages: ["fr"]), .system)
        XCTAssertEqual(InterfaceLanguage(appleLanguages: ["fr", "en"]), .system)
    }

    func testRegionalIdentifiers() {
        XCTAssertEqual(InterfaceLanguage(appleLanguages: ["en-GB"]), .english)
        XCTAssertEqual(InterfaceLanguage(appleLanguages: ["zh-Hans-CN"]), .simplifiedChinese)
        XCTAssertEqual(InterfaceLanguage(appleLanguages: ["zh_CN"]), .simplifiedChinese)
        XCTAssertEqual(InterfaceLanguage(appleLanguages: ["zh-Hant-HK"]), .traditionalChinese)
        XCTAssertEqual(InterfaceLanguage(appleLanguages: ["zh-TW"]), .traditionalChinese)
        XCTAssertEqual(InterfaceLanguage(appleLanguages: ["zh-HK"]), .traditionalChinese)
    }

    func testNativeNames() {
        XCTAssertNil(InterfaceLanguage.system.nativeName)
        XCTAssertEqual(InterfaceLanguage.allCases.compactMap(\.nativeName), ["English", "简体中文", "繁體中文"])
    }
}
