import AppKit

/// Conversions between AppKit screen coordinates (origin at the bottom left
/// of the primary display, y up) and Quartz global coordinates (origin at
/// the top left of the primary display, y down), which Accessibility and
/// CGWindowList use.
@MainActor
enum ScreenGeometry {
    /// The display that holds the global coordinate origin.
    static var primaryScreen: NSScreen? {
        NSScreen.screens.first
    }

    private static var primaryHeight: CGFloat {
        primaryScreen?.frame.height ?? NSScreen.main?.frame.height ?? 0
    }

    static func quartzRect(fromCocoa rect: NSRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func cocoaRect(fromQuartz rect: CGRect) -> NSRect {
        NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func quartzPoint(fromCocoa point: NSPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    static func cocoaPoint(fromQuartz point: CGPoint) -> NSPoint {
        NSPoint(x: point.x, y: primaryHeight - point.y)
    }

    /// The current pointer location in Quartz coordinates.
    static var pointerLocation: CGPoint {
        quartzPoint(fromCocoa: NSEvent.mouseLocation)
    }

    static func screen(containingCocoa point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }

    static func screen(containingQuartz point: CGPoint) -> NSScreen? {
        screen(containingCocoa: cocoaPoint(fromQuartz: point))
    }

    /// Height of the menu bar on `screen`, including the camera housing area.
    static func menuBarHeight(on screen: NSScreen) -> CGFloat {
        let reserved = screen.frame.maxY - screen.visibleFrame.maxY
        if reserved > 0 { return reserved }
        if screen.safeAreaInsets.top > 0 { return screen.safeAreaInsets.top }
        return NSStatusBar.system.thickness
    }

    /// The menu bar strip of `screen` in Cocoa coordinates.
    static func menuBarRect(on screen: NSScreen) -> NSRect {
        let height = menuBarHeight(on: screen)
        return NSRect(x: screen.frame.minX, y: screen.frame.maxY - height, width: screen.frame.width, height: height)
    }

    /// Whether a Cocoa point lies in the menu bar of any screen.
    static func isInMenuBar(cocoa point: NSPoint) -> Bool {
        guard let screen = screen(containingCocoa: point) else { return false }
        // Include the top edge, which NSMouseInRect treats as outside.
        let rect = menuBarRect(on: screen).insetBy(dx: 0, dy: -1)
        return rect.contains(point)
    }

    /// The camera housing ("notch") of `screen` in Cocoa coordinates.
    static func notchRect(on screen: NSScreen) -> NSRect? {
        guard screen.safeAreaInsets.top > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else { return nil }
        let height = screen.safeAreaInsets.top
        return NSRect(x: left.maxX, y: screen.frame.maxY - height, width: right.minX - left.maxX, height: height)
    }

    static func hasNotch(_ screen: NSScreen) -> Bool {
        notchRect(on: screen) != nil
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    static func isBuiltIn(_ screen: NSScreen) -> Bool {
        guard let id = displayID(of: screen) else { return false }
        return CGDisplayIsBuiltin(id) != 0
    }

    static var screenWidths: [Double] {
        NSScreen.screens.map { Double($0.frame.width) }
    }

    /// How far all screens together reach from left to right.
    static var horizontalSpan: Double {
        let frames = NSScreen.screens.map(\.frame)
        guard let minX = frames.map(\.minX).min(), let maxX = frames.map(\.maxX).max() else { return 0 }
        return Double(maxX - minX)
    }

    /// The menu bar of every screen, in Quartz coordinates.
    static var menuBarStrips: [CGRect] {
        NSScreen.screens.map { quartzRect(fromCocoa: menuBarRect(on: $0)) }
    }
}
