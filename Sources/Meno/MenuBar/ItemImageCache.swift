import AppKit
import MenoCore

/// Artwork for menu bar items: the real captured glyph when possible,
/// otherwise the app icon or a matching SF Symbol.
@MainActor
final class ItemImageCache: ObservableObject {
    @Published private(set) var revision = 0

    private var captured: [MenuItemKey: NSImage] = [:]
    /// Symbols the person picked for items, by item key.
    private var customSymbols: [String: String] = [:]
    private var captureTask: Task<Void, Never>?
    /// When all items were last captured.
    private var lastFullCapture: Date?
    /// When each item was last tried, so that one without a window that can
    /// be captured is not tried on every scan.
    private var attempts: [MenuItemKey: Date] = [:]
    /// Counts captures, and names the capture of all items on its way.
    private var generation = 0
    private var fullCaptureGeneration: Int?
    /// How long captures are reused before a window that shows them captures
    /// them again: macOS shows its screen recording indicator each time.
    private static let reuseSpan: TimeInterval = 30

    /// Capturing individual item windows only works up to macOS 26.
    static var captureIsSupported: Bool {
        AppInfo.osMajorVersion < 27
    }

    func capturedImage(for key: MenuItemKey) -> NSImage? {
        captured[key]
    }

    /// The best available image for an item: a symbol the person picked,
    /// the captured artwork, or a fallback.
    func image(for item: MenuBarItem) -> NSImage {
        if let name = customSymbols[item.key.rawValue],
           let symbol = NSImage(systemSymbolName: name, accessibilityDescription: item.displayName) {
            symbol.isTemplate = true
            return symbol
        }
        return captured[item.key] ?? fallbackImage(for: item)
    }

    func setCustomSymbols(_ symbols: [String: String]) {
        guard symbols != customSymbols else { return }
        customSymbols = symbols
        revision += 1
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

    /// Captures the artwork of items. `renew`, for a window that shows the
    /// artwork and just opened, captures all items again once the last
    /// captures are older than ``reuseSpan``; otherwise only items without
    /// artwork yet are captured.
    func refresh(for items: [MenuBarItem], captureAllowed: Bool, renew: Bool = false) {
        guard captureAllowed, Self.captureIsSupported else {
            if !captured.isEmpty {
                captured.removeAll()
                revision += 1
            }
            return
        }
        let now = Date()
        let capturable = items.filter { $0.kind != .marker && $0.frame.width > 0 }
        let isStale = lastFullCapture.map { now.timeIntervalSince($0) >= Self.reuseSpan } ?? true
        let all = renew && isStale
        // A capture of all items on its way covers the missing ones.
        if !all, fullCaptureGeneration != nil { return }
        let wanted = all ? capturable : capturable.filter { item in
            captured[item.key] == nil && (attempts[item.key].map { now.timeIntervalSince($0) >= Self.reuseSpan } ?? true)
        }
        guard !wanted.isEmpty else { return }
        if all {
            lastFullCapture = now
        }
        for item in wanted {
            attempts[item.key] = now
        }
        let requests = wanted.map { WindowCapture.Request(key: $0.key, frame: $0.frame) }
        let present = Set(capturable.map(\.key))
        generation += 1
        let current = generation
        if all {
            fullCaptureGeneration = current
        }
        captureTask?.cancel()
        captureTask = Task { [weak self] in
            let images = await WindowCapture.captureItems(requests)
            guard let self else { return }
            if self.fullCaptureGeneration == current {
                self.fullCaptureGeneration = nil
            }
            guard !Task.isCancelled, self.generation == current else { return }
            // Earlier captures of items still there are kept.
            var updated = all ? [:] : self.captured.filter { present.contains($0.key) }
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
