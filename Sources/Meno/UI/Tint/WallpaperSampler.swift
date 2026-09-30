import AppKit
import ImageIO
import MenoCore

/// What is known about the colors of a screen's wallpaper.
enum WallpaperReading: Equatable, Sendable {
    /// Not read yet.
    case pending
    /// The wallpaper cannot be read, for example a moving one or one in a
    /// folder that macOS protects.
    case unavailable
    case read(WallpaperPalette)
}

/// Finds the colors of each screen's wallpaper under the menu bar. Files
/// are looked at and read off the main thread, and read again only once a
/// wallpaper or its appearance changed.
@MainActor
final class WallpaperSampler {
    /// A screen's wallpaper and how it is shown, taken on the main thread.
    struct Target: Sendable {
        let display: CGDirectDisplayID
        let url: URL
        let screenWidth: Double
        let screenHeight: Double
        let menuBarHeight: Double
        let placement: WallpaperPlacement
        /// The color around a wallpaper that does not fill the screen.
        let fillColor: RGBAColor?
        let dark: Bool
    }

    private var readings: [CGDirectDisplayID: WallpaperReading] = [:]
    private let reader = WallpaperReader()
    private let queue = DispatchQueue(label: "\(AppInfo.bundleIdentifier).wallpaper", qos: .utility)

    func reading(for screen: NSScreen) -> WallpaperReading {
        guard let id = ScreenGeometry.displayID(of: screen) else { return .unavailable }
        return readings[id] ?? .pending
    }

    /// Reads the wallpapers that changed since they were last read, and
    /// calls `changed` once what is known changed.
    func refresh(changed: @escaping @MainActor () -> Void) {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        var targets: [Target] = []
        var present = Set<CGDirectDisplayID>()
        var didChange = false
        for screen in NSScreen.screens {
            guard let id = ScreenGeometry.displayID(of: screen) else { continue }
            present.insert(id)
            // macOS sometimes has no answer for a moment; what was read stays.
            guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else {
                if readings[id] == nil {
                    readings[id] = .unavailable
                    didChange = true
                }
                continue
            }
            let options = NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
            targets.append(Target(
                display: id,
                url: url,
                screenWidth: Double(screen.frame.width),
                screenHeight: Double(screen.frame.height),
                menuBarHeight: Double(ScreenGeometry.menuBarRect(on: screen).height),
                placement: Self.placement(options),
                fillColor: (options[.fillColor] as? NSColor).flatMap(Self.color),
                dark: dark
            ))
        }
        for id in readings.keys where !present.contains(id) {
            readings[id] = nil
            didChange = true
        }
        let reader = self.reader
        let wanted = targets
        let screens = present
        let changedAlready = didChange
        queue.async { [weak self] in
            let results = reader.read(wanted, keeping: screens)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    var didChangeNow = changedAlready
                    for (id, reading) in results where screens.contains(id) && self.readings[id] != reading {
                        self.readings[id] = reading
                        didChangeNow = true
                    }
                    if didChangeNow { changed() }
                }
            }
        }
    }

    private static func placement(_ options: [NSWorkspace.DesktopImageOptionKey: Any]) -> WallpaperPlacement {
        let scaling = (options[.imageScaling] as? NSNumber).flatMap { NSImageScaling(rawValue: $0.uintValue) }
        let clips = (options[.allowClipping] as? NSNumber)?.boolValue ?? true
        switch scaling {
        case .scaleAxesIndependently:
            return .stretch
        case .scaleProportionallyUpOrDown where !clips:
            return .fit
        default:
            // Filling the screen, and a centered or tiled picture, which
            // most often covers the menu bar as well.
            return .fill
        }
    }

    private static func color(_ color: NSColor) -> RGBAColor? {
        guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
        return RGBAColor(red: Double(srgb.redComponent), green: Double(srgb.greenComponent), blue: Double(srgb.blueComponent))
    }
}

/// Reads wallpapers on the sampler's queue, in the order they were asked
/// for, and again only once they or how they are shown changed.
private final class WallpaperReader: @unchecked Sendable {
    private struct Source: Hashable {
        let url: URL
        let modified: Date?
        let screenWidth: Double
        let screenHeight: Double
        let menuBarHeight: Double
        let placement: WallpaperPlacement
        let fillColor: RGBAColor?
        let dark: Bool
    }

    // Only used on the sampler's queue.
    private var current: [CGDirectDisplayID: Source] = [:]
    /// Recent readings, so that going back to a wallpaper, for example in
    /// another Space, needs no reading.
    private var recent: [(source: Source, reading: WallpaperReading)] = []

    func read(_ targets: [WallpaperSampler.Target], keeping present: Set<CGDirectDisplayID>) -> [(CGDirectDisplayID, WallpaperReading)] {
        current = current.filter { present.contains($0.key) }
        var results: [(CGDirectDisplayID, WallpaperReading)] = []
        for target in targets {
            let protected = Self.isProtected(target.url)
            // Looking at a file in a protected folder can have macOS ask the
            // person for access, out of the blue.
            let modified = protected ? nil : (try? target.url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            let source = Source(
                url: target.url,
                modified: modified,
                screenWidth: target.screenWidth,
                screenHeight: target.screenHeight,
                menuBarHeight: target.menuBarHeight,
                placement: target.placement,
                fillColor: target.fillColor,
                dark: target.dark
            )
            guard current[target.display] != source else { continue }
            current[target.display] = source
            let reading: WallpaperReading
            if let known = recent.first(where: { $0.source == source }) {
                reading = known.reading
            } else {
                reading = protected ? .unavailable : Self.reading(of: source)
                recent.insert((source, reading), at: 0)
                if recent.count > 8 { recent.removeLast() }
            }
            results.append((target.display, reading))
        }
        return results
    }

    /// Folders and volumes whose files macOS asks the person about before
    /// an app may read them.
    private static func isProtected(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        if path.hasPrefix("/Volumes/") { return true }
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        return ["Desktop", "Documents", "Downloads", "Library/Mobile Documents", "Library/CloudStorage"].contains { folder in
            path.hasPrefix(home + "/" + folder + "/")
        }
    }

    private static func reading(of source: Source) -> WallpaperReading {
        guard let imageSource = CGImageSourceCreateWithURL(source.url as CFURL, nil) else { return .unavailable }
        let index = imageIndex(of: imageSource, dark: source.dark)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 640,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(imageSource, index, options as CFDictionary) else {
            return .unavailable
        }
        guard let strip = WallpaperPalette.menuBarStrip(
            imageWidth: Double(image.width),
            imageHeight: Double(image.height),
            screenWidth: source.screenWidth,
            screenHeight: source.screenHeight,
            menuBarHeight: source.menuBarHeight,
            placement: source.placement
        ) else {
            // The color around the picture lies under the menu bar.
            return source.fillColor.map { .read(WallpaperPalette(average: $0, leading: $0, trailing: $0)) } ?? .unavailable
        }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let rect = CGRect(x: strip.x, y: strip.y, width: strip.width, height: strip.height).integral.intersection(bounds)
        guard !rect.isEmpty, let cropped = image.cropping(to: rect), let space = CGColorSpace(name: CGColorSpace.sRGB) else {
            return .unavailable
        }
        // A small copy is enough for its colors.
        let width = 96
        let height = 4
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn, let palette = WallpaperPalette(rgba: bytes, width: width, height: height) else { return .unavailable }
        return .read(palette)
    }

    /// The image macOS shows of a wallpaper with a light and a dark version,
    /// as most of its own have, for the appearance.
    private static func imageIndex(of imageSource: CGImageSource, dark: Bool) -> Int {
        let count = CGImageSourceGetCount(imageSource)
        guard count > 1, let metadata = CGImageSourceCopyMetadataAtIndex(imageSource, 0, nil) else { return 0 }
        func value(_ name: String) -> String? {
            CGImageMetadataCopyStringValueWithPath(metadata, nil, "apple_desktop:\(name)" as CFString) as String?
        }
        guard let index = DynamicWallpaper.imageIndex(dark: dark, apr: value("apr"), h24: value("h24"), solar: value("solar")),
              index < count
        else { return 0 }
        return index
    }
}
