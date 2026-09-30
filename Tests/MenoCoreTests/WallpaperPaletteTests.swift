import XCTest
@testable import MenoCore

final class WallpaperPaletteTests: XCTestCase {
    /// An image whose pixels come from `color(x, y)` as 0…255 components.
    private func image(width: Int, height: Int, _ color: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)) -> [UInt8] {
        var bytes: [UInt8] = []
        for y in 0..<height {
            for x in 0..<width {
                let (red, green, blue, alpha) = color(x, y)
                bytes += [red, green, blue, alpha]
            }
        }
        return bytes
    }

    private func assertColor(_ color: RGBAColor, _ red: Double, _ green: Double, _ blue: Double, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(color.red, red, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(color.green, green, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(color.blue, blue, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(color.alpha, 1)
    }

    func testOneColor() throws {
        let bytes = image(width: 8, height: 2) { _, _ in (51, 102, 204, 255) }
        let palette = try XCTUnwrap(WallpaperPalette(rgba: bytes, width: 8, height: 2))
        assertColor(palette.average, 0.2, 0.4, 0.8)
        assertColor(palette.leading, 0.2, 0.4, 0.8)
        assertColor(palette.trailing, 0.2, 0.4, 0.8)
    }

    func testTwoColorsKeepTheirSides() throws {
        // Orange on the left third, blue on the rest.
        let bytes = image(width: 30, height: 3) { x, _ in x < 10 ? (255, 128, 0, 255) : (0, 0, 255, 255) }
        let palette = try XCTUnwrap(WallpaperPalette(rgba: bytes, width: 30, height: 3))
        assertColor(palette.leading, 1, 128.0 / 255, 0)
        assertColor(palette.trailing, 0, 0, 1)
        assertColor(palette.average, 1.0 / 3, 128.0 / 255 / 3, 2.0 / 3)

        let mirrored = image(width: 30, height: 3) { x, _ in x >= 20 ? (255, 128, 0, 255) : (0, 0, 255, 255) }
        let flipped = try XCTUnwrap(WallpaperPalette(rgba: mirrored, width: 30, height: 3))
        assertColor(flipped.leading, 0, 0, 1)
        assertColor(flipped.trailing, 1, 128.0 / 255, 0)
    }

    func testTransparentPixelsAreLeftOut() throws {
        let bytes = image(width: 4, height: 1) { x, _ in x == 0 ? (255, 255, 255, 0) : (0, 255, 0, 255) }
        let palette = try XCTUnwrap(WallpaperPalette(rgba: bytes, width: 4, height: 1))
        assertColor(palette.average, 0, 1, 0)
        XCTAssertNil(WallpaperPalette(rgba: image(width: 2, height: 2) { _, _ in (0, 0, 0, 0) }, width: 2, height: 2))
        XCTAssertNil(WallpaperPalette(rgba: [1, 2, 3], width: 1, height: 1))
        XCTAssertNil(WallpaperPalette(rgba: [], width: 0, height: 0))
    }

    func testMenuBarStripOfAFilledScreen() throws {
        // A 16:9 image on a 16:10 screen is scaled to the screen's height
        // and cut at the sides.
        let strip = try XCTUnwrap(WallpaperPalette.menuBarStrip(
            imageWidth: 1600, imageHeight: 900, screenWidth: 1440, screenHeight: 900, menuBarHeight: 30
        ))
        XCTAssertEqual(strip.x, 80, accuracy: 0.001)
        XCTAssertEqual(strip.y, 0, accuracy: 0.001)
        XCTAssertEqual(strip.width, 1440, accuracy: 0.001)
        XCTAssertEqual(strip.height, 30, accuracy: 0.001)

        // A tall image is scaled to the screen's width and cut at the top.
        let tall = try XCTUnwrap(WallpaperPalette.menuBarStrip(
            imageWidth: 500, imageHeight: 1000, screenWidth: 1000, screenHeight: 500, menuBarHeight: 25
        ))
        XCTAssertEqual(tall.x, 0, accuracy: 0.001)
        XCTAssertEqual(tall.y, 375, accuracy: 0.001)
        XCTAssertEqual(tall.width, 500, accuracy: 0.001)
        XCTAssertEqual(tall.height, 12.5, accuracy: 0.001)

        XCTAssertNil(WallpaperPalette.menuBarStrip(imageWidth: 0, imageHeight: 1, screenWidth: 1, screenHeight: 1, menuBarHeight: 1))
    }
}
