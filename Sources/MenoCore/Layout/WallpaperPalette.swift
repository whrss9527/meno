import Foundation

/// The colors of the part of a wallpaper that lies under the menu bar: its
/// average, and its two main colors in the order they appear from left to
/// right, for a tint that matches the wallpaper.
public struct WallpaperPalette: Equatable, Sendable {
    public var average: RGBAColor
    /// The main color of the left side.
    public var leading: RGBAColor
    /// The main color of the right side.
    public var trailing: RGBAColor

    public init(average: RGBAColor, leading: RGBAColor, trailing: RGBAColor) {
        self.average = average
        self.leading = leading
        self.trailing = trailing
    }

    /// The palette of an image given as RGBA bytes, row by row with four
    /// bytes a pixel and no padding. Transparent pixels are left out.
    /// Returns `nil` for an image without opaque pixels.
    public init?(rgba bytes: [UInt8], width: Int, height: Int) {
        guard width > 0, height > 0, bytes.count >= width * height * 4 else { return nil }
        var pixels: [Pixel] = []
        pixels.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let alpha = Double(bytes[offset + 3]) / 255
                guard alpha > 0.5 else { continue }
                // Stored premultiplied or not, opaque pixels read the same.
                pixels.append(Pixel(
                    red: Double(bytes[offset]) / 255 / alpha,
                    green: Double(bytes[offset + 1]) / 255 / alpha,
                    blue: Double(bytes[offset + 2]) / 255 / alpha,
                    x: (Double(x) + 0.5) / Double(width)
                ))
            }
        }
        guard let average = Self.mean(of: pixels) else { return nil }

        // Two clusters, starting from the left and the right half, so that
        // the result does not depend on chance and keeps its sides.
        var centers = [
            Self.mean(of: pixels.filter { $0.x < 0.5 }) ?? average,
            Self.mean(of: pixels.filter { $0.x >= 0.5 }) ?? average,
        ]
        var members: [[Pixel]] = [pixels, []]
        for _ in 0..<8 {
            var next: [[Pixel]] = [[], []]
            for pixel in pixels {
                let nearest = pixel.distance(to: centers[0]) <= pixel.distance(to: centers[1]) ? 0 : 1
                next[nearest].append(pixel)
            }
            members = next
            let moved = [Self.mean(of: next[0]) ?? centers[0], Self.mean(of: next[1]) ?? centers[1]]
            if moved == centers { break }
            centers = moved
        }
        guard let first = Self.mean(of: members[0]), let second = Self.mean(of: members[1]) else {
            // One color throughout.
            self.init(average: average.color, leading: average.color, trailing: average.color)
            return
        }
        let (leading, trailing) = first.x <= second.x ? (first, second) : (second, first)
        self.init(average: average.color, leading: leading.color, trailing: trailing.color)
    }

    private struct Pixel: Equatable {
        var red: Double
        var green: Double
        var blue: Double
        /// Where the pixel is across the image, 0 at the left edge.
        var x: Double

        func distance(to other: Pixel) -> Double {
            let red = self.red - other.red
            let green = self.green - other.green
            let blue = self.blue - other.blue
            return red * red + green * green + blue * blue
        }

        var color: RGBAColor {
            RGBAColor(red: min(max(red, 0), 1), green: min(max(green, 0), 1), blue: min(max(blue, 0), 1))
        }
    }

    private static func mean(of pixels: [Pixel]) -> Pixel? {
        guard !pixels.isEmpty else { return nil }
        var sum = Pixel(red: 0, green: 0, blue: 0, x: 0)
        for pixel in pixels {
            sum.red += pixel.red
            sum.green += pixel.green
            sum.blue += pixel.blue
            sum.x += pixel.x
        }
        let count = Double(pixels.count)
        return Pixel(red: sum.red / count, green: sum.green / count, blue: sum.blue / count, x: sum.x / count)
    }
}

extension WallpaperPalette {
    /// The part of an image that a screen shows under its menu bar, in the
    /// image's pixels from its top left corner, when the image fills the
    /// screen as wallpapers do by default: scaled to cover it and centered.
    public static func menuBarStrip(
        imageWidth: Double,
        imageHeight: Double,
        screenWidth: Double,
        screenHeight: Double,
        menuBarHeight: Double
    ) -> (x: Double, y: Double, width: Double, height: Double)? {
        guard imageWidth > 0, imageHeight > 0, screenWidth > 0, screenHeight > 0, menuBarHeight > 0 else { return nil }
        let scale = max(screenWidth / imageWidth, screenHeight / imageHeight)
        let x = (imageWidth * scale - screenWidth) / 2 / scale
        let y = (imageHeight * scale - screenHeight) / 2 / scale
        let width = screenWidth / scale
        let height = max(min(menuBarHeight, screenHeight) / scale, 1)
        return (x, y, width, min(height, imageHeight - y))
    }
}
