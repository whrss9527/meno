import XCTest
@testable import MenoCore

final class GlyphAnalysisTests: XCTestCase {
    private func image(_ pixels: [(UInt8, UInt8, UInt8, UInt8)]) -> [UInt8] {
        pixels.flatMap { [$0.0, $0.1, $0.2, $0.3] }
    }

    func testWhiteAndBlackGlyphsAreMonochrome() {
        let white = image([(255, 255, 255, 255), (0, 0, 0, 0), (128, 128, 128, 128)])
        XCTAssertTrue(GlyphAnalysis.isMonochrome(rgba: white, width: 3, height: 1))
        let black = image([(0, 0, 0, 255), (0, 0, 0, 200), (0, 0, 0, 0)])
        XCTAssertTrue(GlyphAnalysis.isMonochrome(rgba: black, width: 3, height: 1))
    }

    func testColoredArtworkIsNot() {
        let colored = image([(255, 0, 0, 255), (0, 200, 0, 255), (255, 255, 255, 255)])
        XCTAssertFalse(GlyphAnalysis.isMonochrome(rgba: colored, width: 3, height: 1))
    }

    func testAFewColoredPixelsAreTolerated() {
        var pixels = Array(repeating: (UInt8(255), UInt8(255), UInt8(255), UInt8(255)), count: 99)
        pixels.append((255, 0, 0, 255))
        XCTAssertTrue(GlyphAnalysis.isMonochrome(rgba: image(pixels), width: 100, height: 1))
    }

    func testTransparentImagesAreNotMonochrome() {
        let empty = image([(0, 0, 0, 0), (10, 10, 10, 20)])
        XCTAssertFalse(GlyphAnalysis.isMonochrome(rgba: empty, width: 2, height: 1))
    }
}
