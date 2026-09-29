import Foundation

/// A coarse fingerprint of a menu bar item's artwork, for noticing when an
/// item changes (for example when a sync fails and its icon shows a badge).
///
/// The artwork is reduced to a grid of cells. Each cell keeps how much of it
/// is covered and, for colored artwork, a rough hue. Brightness is left out,
/// because single-color glyphs switch between white and black with the menu
/// bar behind them, which is not a change of the item.
public struct GlyphSignature: Equatable, Sendable {
    public static let side = 16

    /// Coverage level (0–3) in the low two bits, hue bucket (0 for gray,
    /// 1–6 for colors) above them.
    public let cells: [UInt8]

    /// - Parameter rgba: Premultiplied RGBA pixels, row by row.
    public init(rgba: [UInt8], width: Int, height: Int) {
        let side = Self.side
        var cells = [UInt8](repeating: 0, count: side * side)
        guard width > 0, height > 0, rgba.count >= width * height * 4 else {
            self.cells = cells
            return
        }
        for cellY in 0..<side {
            let y0 = cellY * height / side
            let y1 = max(y0 + 1, (cellY + 1) * height / side)
            for cellX in 0..<side {
                let x0 = cellX * width / side
                let x1 = max(x0 + 1, (cellX + 1) * width / side)
                var alphaSum = 0.0
                var red = 0.0, green = 0.0, blue = 0.0
                var visible = 0.0
                var count = 0.0
                for y in y0..<min(y1, height) {
                    for x in x0..<min(x1, width) {
                        let index = (y * width + x) * 4
                        let alpha = Double(rgba[index + 3])
                        alphaSum += alpha / 255
                        count += 1
                        guard alpha > 40 else { continue }
                        red += Double(rgba[index]) / alpha
                        green += Double(rgba[index + 1]) / alpha
                        blue += Double(rgba[index + 2]) / alpha
                        visible += 1
                    }
                }
                guard count > 0 else { continue }
                let coverage = alphaSum / count
                let level: UInt8 = coverage < 0.15 ? 0 : coverage < 0.45 ? 1 : coverage < 0.75 ? 2 : 3
                var hue: UInt8 = 0
                if level > 0, visible > 0 {
                    hue = Self.hueBucket(red: red / visible, green: green / visible, blue: blue / visible)
                }
                cells[cellY * side + cellX] = level | (hue << 2)
            }
        }
        self.cells = cells
    }

    public init(cells: [UInt8]) {
        self.cells = cells
    }

    /// The share of covered cells that differ, from 0 (same) to 1.
    public func difference(from other: GlyphSignature) -> Double {
        guard cells.count == other.cells.count else { return 1 }
        var covered = 0
        var different = 0
        for (a, b) in zip(cells, other.cells) where a & 3 != 0 || b & 3 != 0 {
            covered += 1
            if a != b { different += 1 }
        }
        return covered == 0 ? 0 : Double(different) / Double(covered)
    }

    /// Whether the artwork changed noticeably.
    public func differs(from other: GlyphSignature, threshold: Double = 0.12) -> Bool {
        difference(from: other) > threshold
    }

    /// 0 for grays, otherwise one of six hue sectors.
    static func hueBucket(red: Double, green: Double, blue: Double) -> UInt8 {
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let spread = maximum - minimum
        guard spread > 0.25 else { return 0 }
        var hue: Double
        if maximum == red {
            hue = (green - blue) / spread
        } else if maximum == green {
            hue = 2 + (blue - red) / spread
        } else {
            hue = 4 + (red - green) / spread
        }
        hue = (hue < 0 ? hue + 6 : hue)
        return UInt8(min(5, Int(hue))) + 1
    }
}
