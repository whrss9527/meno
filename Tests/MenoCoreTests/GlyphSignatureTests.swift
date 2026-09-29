import XCTest
@testable import MenoCore

final class GlyphSignatureTests: XCTestCase {
    /// A transparent image with filled rectangles, as premultiplied RGBA.
    private func image(
        width: Int = 36, height: Int = 22,
        _ shapes: [(x: Range<Int>, y: Range<Int>, color: (UInt8, UInt8, UInt8), alpha: UInt8)]
    ) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for shape in shapes {
            for y in shape.y where y < height {
                for x in shape.x where x < width {
                    let index = (y * width + x) * 4
                    let alpha = Double(shape.alpha) / 255
                    pixels[index] = UInt8(Double(shape.color.0) * alpha)
                    pixels[index + 1] = UInt8(Double(shape.color.1) * alpha)
                    pixels[index + 2] = UInt8(Double(shape.color.2) * alpha)
                    pixels[index + 3] = shape.alpha
                }
            }
        }
        return pixels
    }

    private func signature(_ pixels: [UInt8], width: Int = 36, height: Int = 22) -> GlyphSignature {
        GlyphSignature(rgba: pixels, width: width, height: height)
    }

    private let cloud = (x: 6..<30, y: 6..<16)

    func testSameArtworkIsUnchanged() {
        let a = signature(image([(cloud.x, cloud.y, (255, 255, 255), 255)]))
        let b = signature(image([(cloud.x, cloud.y, (255, 255, 255), 255)]))
        XCTAssertEqual(a.difference(from: b), 0)
        XCTAssertFalse(a.differs(from: b))
    }

    func testMenuBarAppearanceIsNotAChange() {
        // The same glyph drawn white on a dark menu bar and black on a light one.
        let white = signature(image([(cloud.x, cloud.y, (255, 255, 255), 255)]))
        let black = signature(image([(cloud.x, cloud.y, (0, 0, 0), 255)]))
        XCTAssertFalse(white.differs(from: black))
    }

    func testBadgeIsAChange() {
        let plain = signature(image([(cloud.x, cloud.y, (0, 0, 0), 255)]))
        let badged = signature(image([(cloud.x, cloud.y, (0, 0, 0), 255), (26..<34, 0..<8, (255, 59, 48), 255)]))
        XCTAssertTrue(badged.differs(from: plain))
    }

    func testColorChangeIsAChange() {
        let green = signature(image([(cloud.x, cloud.y, (52, 199, 89), 255)]))
        let red = signature(image([(cloud.x, cloud.y, (255, 59, 48), 255)]))
        XCTAssertTrue(red.differs(from: green))
    }

    func testDifferentShapeIsAChange() {
        let wide = signature(image([(cloud.x, cloud.y, (0, 0, 0), 255)]))
        let narrow = signature(image([(14..<22, 2..<20, (0, 0, 0), 255)]))
        XCTAssertTrue(narrow.differs(from: wide))
    }

    func testFaintEdgesAreNotAChange() {
        let sharp = signature(image([(cloud.x, cloud.y, (0, 0, 0), 255)]))
        let softened = signature(image([(cloud.x, cloud.y, (0, 0, 0), 255), (5..<6, cloud.y, (0, 0, 0), 30)]))
        XCTAssertFalse(softened.differs(from: sharp))
    }

    func testEmptyArtwork() {
        let empty = signature(image([]))
        XCTAssertEqual(empty.difference(from: empty), 0)
        XCTAssertEqual(GlyphSignature(rgba: [], width: 0, height: 0).cells.count, GlyphSignature.side * GlyphSignature.side)
    }

    func testHueBuckets() {
        XCTAssertEqual(GlyphSignature.hueBucket(red: 0.5, green: 0.5, blue: 0.5), 0)
        XCTAssertEqual(GlyphSignature.hueBucket(red: 1, green: 0, blue: 0), 1)
        XCTAssertEqual(GlyphSignature.hueBucket(red: 0, green: 1, blue: 0), 3)
        XCTAssertEqual(GlyphSignature.hueBucket(red: 0, green: 0, blue: 1), 5)
    }
}
