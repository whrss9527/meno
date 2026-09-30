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
        let smaller = min(members[0].count, members[1].count)
        if Double(smaller) < Double(pixels.count) * Self.smallestShare {
            // A small patch, such as the moon in a night sky, would light up
            // one end: the main color covers both.
            let main = members[0].count >= members[1].count ? first : second
            self.init(average: average.color, leading: main.color, trailing: main.color)
            return
        }
        if abs(first.x - second.x) < Self.smallestSeparation {
            // Two colors mixed throughout, such as stripes, have no sides.
            self.init(average: average.color, leading: average.color, trailing: average.color)
            return
        }
        let (leading, trailing) = first.x <= second.x ? (first, second) : (second, first)
        self.init(average: average.color, leading: leading.color, trailing: trailing.color)
    }

    /// The share of the pixels a color needs to become an end of a gradient.
    static let smallestShare = 0.2
    /// How far apart across the image, as a share of its width, two colors
    /// have to lie on average to count as its left and its right side.
    static let smallestSeparation = 0.15

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

/// How a wallpaper is laid out on a screen.
public enum WallpaperPlacement: Sendable {
    /// Scaled to cover the screen and centered, the default.
    case fill
    /// Scaled to fit inside the screen and centered, with a color around it.
    case fit
    /// Scaled to the screen's width and height separately.
    case stretch
}

extension WallpaperPalette {
    /// The part of an image that a screen shows under its menu bar, in the
    /// image's pixels from its top left corner. `nil` when the image does
    /// not reach the menu bar, as when it fits a screen of another shape.
    public static func menuBarStrip(
        imageWidth: Double,
        imageHeight: Double,
        screenWidth: Double,
        screenHeight: Double,
        menuBarHeight: Double,
        placement: WallpaperPlacement = .fill
    ) -> (x: Double, y: Double, width: Double, height: Double)? {
        guard imageWidth > 0, imageHeight > 0, screenWidth > 0, screenHeight > 0, menuBarHeight > 0 else { return nil }
        let bar = min(menuBarHeight, screenHeight)
        switch placement {
        case .fill:
            let scale = max(screenWidth / imageWidth, screenHeight / imageHeight)
            let x = (imageWidth * scale - screenWidth) / 2 / scale
            let y = (imageHeight * scale - screenHeight) / 2 / scale
            let height = max(bar / scale, 1)
            return (x, y, screenWidth / scale, min(height, imageHeight - y))
        case .fit:
            let scale = min(screenWidth / imageWidth, screenHeight / imageHeight)
            // The color around the image lies above it, too.
            let top = (screenHeight - imageHeight * scale) / 2
            guard top < bar else { return nil }
            let height = max((bar - top) / scale, 1)
            return (0, 0, imageWidth, min(height, imageHeight))
        case .stretch:
            let height = max(bar * imageHeight / screenHeight, 1)
            return (0, 0, imageWidth, min(height, imageHeight))
        }
    }
}

/// Wallpapers with a light and a dark version, as macOS's own are, keep
/// which of their images is which in their `apple_desktop` metadata.
public enum DynamicWallpaper {
    /// The image to use in Dark Mode or not, from the metadata values
    /// `apr` (light and dark), `h24` (time of day) or `solar` (sun), each
    /// a Base64 property list. `nil` without a light and a dark version.
    public static func imageIndex(dark: Bool, apr: String?, h24: String?, solar: String?) -> Int? {
        if let appearance = propertyList(apr) {
            return index(in: appearance, dark: dark)
        }
        for value in [h24, solar] {
            if let appearance = propertyList(value)?["ap"] as? [String: Any] {
                return index(in: appearance, dark: dark)
            }
        }
        return nil
    }

    private static func propertyList(_ base64: String?) -> [String: Any]? {
        guard let base64, let data = Data(base64Encoded: base64.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
    }

    private static func index(in appearance: [String: Any], dark: Bool) -> Int? {
        guard let value = appearance[dark ? "d" : "l"] else { return nil }
        if let number = value as? Int { return number >= 0 ? number : nil }
        if let number = value as? NSNumber { return number.intValue >= 0 ? number.intValue : nil }
        return nil
    }
}
