import AppKit
import MenoCore

/// Draws the template images Meno shows in the menu bar.
enum MenoIconRenderer {
    static let canvas = NSSize(width: 18, height: 18)

    /// The image of the Meno icon for a style and state.
    static func toggleImage(for icon: MenoIcon, revealed: Bool) -> NSImage {
        if let names = icon.symbolNames,
           let image = symbol(revealed ? names.revealed : names.collapsed) {
            return image
        }
        return menoGlyph(revealed: revealed)
    }

    /// Meno's own artwork: three bars of increasing height, like icons in a
    /// menu bar. They fan out while items are revealed and fold together
    /// while items are hidden.
    static func menoGlyph(revealed: Bool) -> NSImage {
        let image = NSImage(size: canvas, flipped: false) { rect in
            let heights: [CGFloat] = [7.5, 10.5, 13.5]
            let alphas: [CGFloat] = [0.42, 0.68, 1.0]
            let width: CGFloat = 3.2
            let origins: [CGFloat] = revealed ? [2.0, 7.4, 12.8] : [5.2, 8.0, 10.8]
            for index in 0..<3 {
                let height = heights[index]
                let bar = NSRect(x: origins[index], y: (rect.height - height) / 2, width: width, height: height)
                NSColor.black.withAlphaComponent(alphas[index]).setFill()
                NSBezierPath(roundedRect: bar, xRadius: width / 2, yRadius: width / 2).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// The glyph shown while Zen is on.
    static func zenGlyph() -> NSImage {
        symbol("leaf.fill", pointSize: 13) ?? menoGlyph(revealed: false)
    }

    /// A divider glyph. `double` distinguishes the Stash divider.
    static func dividerImage(_ glyph: DividerGlyph, double: Bool) -> NSImage {
        let width: CGFloat
        switch glyph {
        case .chevron: width = double ? 13 : 9
        case .line: width = double ? 8 : 5
        case .dot: width = 8
        }
        let image = NSImage(size: NSSize(width: width, height: canvas.height), flipped: false) { rect in
            NSColor.black.withAlphaComponent(0.6).set()
            switch glyph {
            case .chevron:
                let offsets: [CGFloat] = double ? [-2.5, 2.5] : [0]
                for offset in offsets {
                    let path = NSBezierPath()
                    let x = rect.midX + offset
                    path.move(to: NSPoint(x: x + 2, y: rect.midY + 4.5))
                    path.line(to: NSPoint(x: x - 2, y: rect.midY))
                    path.line(to: NSPoint(x: x + 2, y: rect.midY - 4.5))
                    path.lineWidth = 1.6
                    path.lineCapStyle = .round
                    path.lineJoinStyle = .round
                    path.stroke()
                }
            case .line:
                let offsets: [CGFloat] = double ? [-1.6, 1.6] : [0]
                for offset in offsets {
                    let bar = NSRect(x: rect.midX + offset - 0.7, y: rect.midY - 6.5, width: 1.4, height: 13)
                    NSBezierPath(roundedRect: bar, xRadius: 0.7, yRadius: 0.7).fill()
                }
            case .dot:
                let offsets: [CGFloat] = double ? [-3, 3] : [0]
                for offset in offsets {
                    let dot = NSRect(x: rect.midX - 2, y: rect.midY + offset - 2, width: 4, height: 4)
                    NSBezierPath(ovalIn: dot).fill()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    static func symbol(_ name: String, pointSize: CGFloat = 14, weight: NSFont.Weight = .medium) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return nil }
        image.isTemplate = true
        return image
    }
}
