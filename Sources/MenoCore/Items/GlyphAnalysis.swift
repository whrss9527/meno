import Foundation

/// Looks at the pixels of captured menu bar artwork.
public enum GlyphAnalysis {
    /// Whether the visible pixels of an image are all shades of gray.
    ///
    /// Most menu bar glyphs are drawn in one color that depends on the menu
    /// bar behind them: white over a dark wallpaper, black over a light one.
    /// Such captures read better in the text color of wherever Meno shows
    /// them. `rgba` holds 8-bit channels with premultiplied alpha.
    public static func isMonochrome(rgba: [UInt8], width: Int, height: Int) -> Bool {
        var visible = 0
        var colored = 0
        let count = min(rgba.count / 4, width * height)
        for index in 0..<count {
            let offset = index * 4
            let alpha = Double(rgba[offset + 3])
            guard alpha > 40 else { continue }
            visible += 1
            let red = Double(rgba[offset]) / alpha
            let green = Double(rgba[offset + 1]) / alpha
            let blue = Double(rgba[offset + 2]) / alpha
            if max(red, green, blue) - min(red, green, blue) > 0.2 {
                colored += 1
            }
        }
        return visible > 0 && Double(colored) <= Double(visible) * 0.05
    }
}
