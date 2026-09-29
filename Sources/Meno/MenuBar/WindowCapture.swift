import CoreGraphics
import Darwin
import Foundation
import MenoCore

/// Captures the artwork of menu bar items from their windows.
///
/// Up to macOS 26 every menu bar item is a small window, which can be
/// captured with Screen Recording permission even when the item is pushed off
/// screen. On macOS 27 the menu bar is a single window, so Meno falls back
/// to app icons there.
enum WindowCapture {
    struct Request: Sendable {
        let key: MenuItemKey
        let frame: CGRect
    }

    struct WindowInfo: Sendable {
        let id: CGWindowID
        let pid: pid_t
        let layer: Int
        let bounds: CGRect
        let isOnScreen: Bool
    }

    static func captureItems(_ requests: [Request]) async -> [MenuItemKey: CGImage] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
                let windows = windowList(onScreenOnly: false).filter { $0.layer == statusLevel }
                var result: [MenuItemKey: CGImage] = [:]
                for request in requests {
                    guard let window = windows.first(where: { matches($0.bounds, request.frame) }),
                          let image = capture(windowID: window.id) else { continue }
                    result[request.key] = image
                }
                continuation.resume(returning: result)
            }
        }
    }

    static func windowList(onScreenOnly: Bool) -> [WindowInfo] {
        let options: CGWindowListOption = onScreenOnly ? [.optionOnScreenOnly, .excludeDesktopElements] : [.optionAll]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { entry in
            guard let number = entry[kCGWindowNumber as String] as? NSNumber,
                  let pid = entry[kCGWindowOwnerPID as String] as? NSNumber,
                  let layer = entry[kCGWindowLayer as String] as? NSNumber,
                  let boundsDictionary = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary) else { return nil }
            let onScreen = (entry[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
            return WindowInfo(id: number.uint32Value, pid: pid.int32Value, layer: layer.intValue, bounds: bounds, isOnScreen: onScreen)
        }
    }

    /// Whether `pid` shows a menu, popover or panel right now (used to wait
    /// until an opened item is dismissed).
    static func hasOpenPopup(ownedBy pid: pid_t, menuBarHeight: CGFloat) -> Bool {
        let floating = Int(CGWindowLevelForKey(.floatingWindow))
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        return windowList(onScreenOnly: true).contains { window in
            guard window.pid == pid, window.layer >= floating else { return false }
            // Skip the status item windows themselves.
            let isStatusItem = window.layer == statusLevel && window.bounds.minY <= 1 && window.bounds.height <= menuBarHeight + 2
            return !isStatusItem && window.bounds.width > 4 && window.bounds.height > 4
        }
    }

    /// Whether any app currently shows a menu.
    static func anyMenuOpen() -> Bool {
        let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        return windowList(onScreenOnly: true).contains { $0.layer == menuLevel && $0.bounds.height > 4 }
    }

    private static func matches(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 2 && abs(a.width - b.width) <= 2 && abs(a.minY - b.minY) <= 4
    }

    // `CGWindowListCreateImage` is marked unavailable in recent SDKs in favor
    // of ScreenCaptureKit, but it is still the only way to capture windows
    // that sit outside the visible screen area. It is looked up at runtime.
    private typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    private static let createImage: CreateImage? = {
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY),
              let symbol = dlsym(handle, "CGWindowListCreateImage") else { return nil }
        return unsafeBitCast(symbol, to: CreateImage.self)
    }()

    /// Whether a capture is a single-color glyph, as most menu bar items are.
    static func isMonochrome(_ image: CGImage) -> Bool {
        let width = min(image.width, 64)
        let height = max(1, Int((Double(image.height) * Double(width) / Double(max(image.width, 1))).rounded()))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn && GlyphAnalysis.isMonochrome(rgba: pixels, width: width, height: height)
    }

    static func capture(windowID: CGWindowID) -> CGImage? {
        guard let createImage else { return nil }
        let listOption = CGWindowListOption.optionIncludingWindow.rawValue
        let imageOption = CGWindowImageOption([.boundsIgnoreFraming, .bestResolution]).rawValue
        guard let image = createImage(.null, listOption, windowID, imageOption)?.takeRetainedValue(),
              image.width > 1, image.height > 1 else { return nil }
        return image
    }
}
