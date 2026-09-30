import AppKit
import ImageIO
import MenoCore

/// What is known about the colors of a screen's wallpaper.
enum WallpaperReading: Equatable {
    /// Not read yet.
    case pending
    /// The wallpaper could not be read, for example a moving one.
    case unavailable
    case read(WallpaperPalette)
}

/// Finds the colors of each screen's wallpaper under the menu bar. Images
/// are read off the main thread, and again only once a wallpaper changed.
@MainActor
final class WallpaperSampler {
    /// What a reading was made from.
    private struct Source: Equatable, Sendable {
        let url: URL
        let modified: Date?
        let screenSize: CGSize
        let menuBarHeight: CGFloat
    }

    /// What is known of each screen's wallpaper, and what it was read from.
    private var readings: [CGDirectDisplayID: (source: Source?, reading: WallpaperReading)] = [:]
    /// Readings on their way, so that they are not made twice.
    private var inFlight: [CGDirectDisplayID: Source] = [:]
    private let queue = DispatchQueue(label: "\(AppInfo.bundleIdentifier).wallpaper", qos: .utility)

    func reading(for screen: NSScreen) -> WallpaperReading {
        guard let id = ScreenGeometry.displayID(of: screen) else { return .unavailable }
        return readings[id]?.reading ?? .pending
    }

    /// Reads the wallpapers that changed since they were last read, and
    /// calls `changed` once what is known changed.
    func refresh(changed: @escaping @MainActor () -> Void) {
        var didChange = false
        var work: [(id: CGDirectDisplayID, source: Source)] = []
        var present = Set<CGDirectDisplayID>()
        for screen in NSScreen.screens {
            guard let id = ScreenGeometry.displayID(of: screen) else { continue }
            present.insert(id)
            guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else {
                inFlight[id] = nil
                if readings[id]?.reading != .unavailable {
                    readings[id] = (nil, .unavailable)
                    didChange = true
                }
                continue
            }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            let source = Source(
                url: url,
                modified: modified,
                screenSize: screen.frame.size,
                menuBarHeight: ScreenGeometry.menuBarRect(on: screen).height
            )
            guard readings[id]?.source != source, inFlight[id] != source else { continue }
            inFlight[id] = source
            work.append((id, source))
        }
        for id in readings.keys where !present.contains(id) {
            readings[id] = nil
            inFlight[id] = nil
            didChange = true
        }
        if didChange {
            // Not right away: the caller may be drawing with what it knew.
            Task { @MainActor in changed() }
        }
        guard !work.isEmpty else { return }
        queue.async { [weak self] in
            let results = work.map { entry in
                (entry.id, entry.source, Self.read(entry.source).map(WallpaperReading.read) ?? .unavailable)
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    var didChange = false
                    // A reading that a newer one replaced meanwhile is dropped.
                    for (id, source, result) in results where self.inFlight[id] == source {
                        self.inFlight[id] = nil
                        if self.readings[id]?.reading != result { didChange = true }
                        self.readings[id] = (source, result)
                    }
                    if didChange { changed() }
                }
            }
        }
    }

    /// The palette of the part of the wallpaper under the menu bar.
    nonisolated private static func read(_ source: Source) -> WallpaperPalette? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 640,
        ]
        guard let imageSource = CGImageSourceCreateWithURL(source.url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary),
              let strip = WallpaperPalette.menuBarStrip(
                  imageWidth: Double(image.width),
                  imageHeight: Double(image.height),
                  screenWidth: Double(source.screenSize.width),
                  screenHeight: Double(source.screenSize.height),
                  menuBarHeight: Double(source.menuBarHeight)
              )
        else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let rect = CGRect(x: strip.x, y: strip.y, width: strip.width, height: strip.height).integral.intersection(bounds)
        guard !rect.isEmpty, let cropped = image.cropping(to: rect), let space = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
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
        guard drawn else { return nil }
        return WallpaperPalette(rgba: bytes, width: width, height: height)
    }
}
