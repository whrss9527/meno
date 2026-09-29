import AppKit
import MenoCore

/// Artwork for menu bar items: the real captured glyph when possible,
/// otherwise the app icon or a matching SF Symbol.
@MainActor
final class ItemImageCache: ObservableObject {
    @Published private(set) var revision = 0

    private var captured: [MenuItemKey: NSImage] = [:]
    private var captureTask: Task<Void, Never>?
    private var lastCapture: Date?

    /// Capturing individual item windows only works up to macOS 26.
    static var captureIsSupported: Bool {
        AppInfo.osMajorVersion < 27
    }

    func capturedImage(for key: MenuItemKey) -> NSImage? {
        captured[key]
    }

    /// The best available image for an item.
    func image(for item: MenuBarItem) -> NSImage {
        captured[item.key] ?? fallbackImage(for: item)
    }

    /// The app icon (or symbol) for an item, ignoring captures.
    func fallbackImage(for item: MenuBarItem) -> NSImage {
        if item.kind == .marker {
            return NSImage(systemSymbolName: "character.cursor.ibeam", accessibilityDescription: nil) ?? NSImage()
        }
        if item.kind == .system,
           let symbol = Self.systemSymbolName(for: item),
           let image = NSImage(systemSymbolName: symbol, accessibilityDescription: item.displayName) {
            return image
        }
        if let icon = item.runningApplication?.icon {
            return icon
        }
        return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
    }

    func refresh(for items: [MenuBarItem], captureAllowed: Bool, force: Bool = false) {
        guard captureAllowed, Self.captureIsSupported else {
            if !captured.isEmpty {
                captured.removeAll()
                revision += 1
            }
            return
        }
        if !force, let lastCapture, Date().timeIntervalSince(lastCapture) < 2 { return }
        lastCapture = Date()
        let requests = items
            .filter { $0.kind != .marker && $0.frame.width > 0 }
            .map { WindowCapture.Request(key: $0.key, frame: $0.frame) }
        captureTask?.cancel()
        captureTask = Task { [weak self] in
            let images = await WindowCapture.captureItems(requests)
            guard let self, !Task.isCancelled else { return }
            var updated: [MenuItemKey: NSImage] = [:]
            for (key, image) in images {
                let scale = NSScreen.main?.backingScaleFactor ?? 2
                let size = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
                let glyph = NSImage(cgImage: image, size: size)
                // Single-color glyphs follow the text color where Meno shows
                // them, so white glyphs stay visible on light surfaces.
                glyph.isTemplate = WindowCapture.isMonochrome(image)
                updated[key] = glyph
            }
            self.captured = updated
            self.revision += 1
        }
    }

    static func systemSymbolName(for item: MenuBarItem) -> String? {
        let haystack = [(item.identifier ?? ""), item.displayName]
            .joined(separator: " ")
            .lowercased()
            .replacingOccurrences(of: "\u{2011}", with: "-")
        let table: [(String, String)] = [
            ("wifi", "wifi"), ("wi-fi", "wifi"), ("battery", "battery.75"),
            ("bluetooth", "dot.radiowaves.left.and.right"), ("sound", "speaker.wave.2.fill"),
            ("volume", "speaker.wave.2.fill"), ("focus", "moon.fill"), ("donotdisturb", "moon.fill"),
            ("screenmirroring", "rectangle.on.rectangle"), ("airplay", "airplayvideo"),
            ("display", "display"), ("nowplaying", "play.circle"), ("now playing", "play.circle"),
            ("clock", "clock"), ("spotlight", "magnifyingglass"), ("siri", "mic.circle"),
            ("controlcenter", "switch.2"), ("control center", "switch.2"),
            ("user", "person.crop.circle"), ("textinput", "keyboard"), ("input", "keyboard"),
            ("keyboard", "keyboard"), ("timemachine", "clock.arrow.circlepath"),
            ("time machine", "clock.arrow.circlepath"), ("vpn", "network"),
            ("accessibility", "accessibility"), ("stage", "rectangle.split.3x1"),
            ("weather", "cloud.sun"), ("script", "applescript"), ("airdrop", "dot.radiowaves.up.forward"),
            ("hearing", "ear"), ("gamemode", "gamecontroller"), ("game mode", "gamecontroller"),
        ]
        return table.first { haystack.contains($0.0) }?.1
    }
}
