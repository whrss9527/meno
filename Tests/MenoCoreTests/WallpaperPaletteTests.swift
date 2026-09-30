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

    func testASmallPatchDoesNotBecomeAnEnd() throws {
        // A night sky with a small moon on the right.
        let bytes = image(width: 64, height: 6) { x, y in
            (54...58).contains(x) && (1...4).contains(y) ? (240, 235, 200, 255) : (10, 20, 40, 255)
        }
        let palette = try XCTUnwrap(WallpaperPalette(rgba: bytes, width: 64, height: 6))
        assertColor(palette.leading, 10.0 / 255, 20.0 / 255, 40.0 / 255)
        assertColor(palette.trailing, 10.0 / 255, 20.0 / 255, 40.0 / 255)
    }

    func testMixedColorsHaveNoSides() throws {
        // Stripes of two colors all across.
        let bytes = image(width: 40, height: 2) { x, _ in x % 2 == 0 ? (255, 0, 0, 255) : (0, 0, 255, 255) }
        let palette = try XCTUnwrap(WallpaperPalette(rgba: bytes, width: 40, height: 2))
        assertColor(palette.leading, 0.5, 0, 0.5)
        assertColor(palette.trailing, 0.5, 0, 0.5)
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

    func testMenuBarStripOfOtherPlacements() throws {
        // Stretched, the top rows of the image in its full width.
        let stretched = try XCTUnwrap(WallpaperPalette.menuBarStrip(
            imageWidth: 1000, imageHeight: 1000, screenWidth: 1600, screenHeight: 1000, menuBarHeight: 25, placement: .stretch
        ))
        XCTAssertEqual(stretched.x, 0)
        XCTAssertEqual(stretched.width, 1000)
        XCTAssertEqual(stretched.height, 25, accuracy: 0.001)

        // Fitted to a wider screen, the image reaches the top.
        let wide = try XCTUnwrap(WallpaperPalette.menuBarStrip(
            imageWidth: 1000, imageHeight: 1000, screenWidth: 1600, screenHeight: 1000, menuBarHeight: 25, placement: .fit
        ))
        XCTAssertEqual(wide.y, 0)
        XCTAssertEqual(wide.height, 25, accuracy: 0.001)

        // Fitted to a taller screen, the color around it lies under the menu bar.
        XCTAssertNil(WallpaperPalette.menuBarStrip(
            imageWidth: 1600, imageHeight: 900, screenWidth: 1440, screenHeight: 900, menuBarHeight: 30, placement: .fit
        ))
    }

    func testDynamicWallpaperImages() throws {
        func base64(_ plist: [String: Any]) throws -> String {
            try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0).base64EncodedString()
        }
        let appearance = try base64(["l": 0, "d": 1])
        XCTAssertEqual(DynamicWallpaper.imageIndex(dark: false, apr: appearance, h24: nil, solar: nil), 0)
        XCTAssertEqual(DynamicWallpaper.imageIndex(dark: true, apr: appearance, h24: nil, solar: nil), 1)

        let solar = try base64(["ap": ["l": 2, "d": 13], "si": [["a": -0.3, "i": 0, "z": 270.9]]])
        XCTAssertEqual(DynamicWallpaper.imageIndex(dark: true, apr: nil, h24: nil, solar: solar), 13)
        let h24 = try base64(["ap": ["l": 3, "d": 7], "ti": [["i": 0, "t": 0.25]]])
        XCTAssertEqual(DynamicWallpaper.imageIndex(dark: false, apr: nil, h24: h24, solar: solar), 3)

        XCTAssertNil(DynamicWallpaper.imageIndex(dark: true, apr: nil, h24: nil, solar: nil))
        XCTAssertNil(DynamicWallpaper.imageIndex(dark: true, apr: "not base64", h24: nil, solar: nil))
        XCTAssertNil(DynamicWallpaper.imageIndex(dark: true, apr: try base64(["x": 1]), h24: nil, solar: nil))
    }
}
