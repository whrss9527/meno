import AppKit
import Combine
import MenoCore
import SwiftUI

/// Paints a tint, border or shadow behind the menu bar (experimental).
///
/// The overlay is a click-through window just below the menu bar's level,
/// so menus and items stay on top of it.
@MainActor
final class TintOverlayController {
    unowned let model: AppModel

    private var panels: [CGDirectDisplayID: FloatingPanel] = [:]
    private var subscriptions: Set<AnyCancellable> = []
    private var subscribed = false
    private let wallpaper = WallpaperSampler()
    /// Looks at the wallpapers again while the tint takes their colors.
    private var wallpaperWatch: Task<Void, Never>?
    private var spaceObserver: NSObjectProtocol?
    private var appearanceObservation: NSKeyValueObservation?

    init(model: AppModel) {
        self.model = model
    }

    /// Draws the tint again after the screens changed, or the Mac woke,
    /// and looks at their wallpapers again.
    func screensChanged() {
        update()
        if wallpaperWatch != nil {
            refreshWallpaper()
        }
    }

    func update() {
        let tint = model.settings.tint
        guard tint.enabled else {
            removeAll()
            watchWallpaper(false)
            return
        }
        subscribeIfNeeded()
        let usesWallpaper = tint.colorSource == .wallpaper
        watchWallpaper(usesWallpaper)
        // With "Automatically hide and show the menu bar" the tint would sit
        // on top of windows, so it is only drawn where the bar is reserved.
        let menuBarAutoHides = UserDefaults.standard.bool(forKey: "_HIHideMenuBar")
        var seen = Set<CGDirectDisplayID>()
        for screen in NSScreen.screens {
            guard let id = ScreenGeometry.displayID(of: screen),
                  !menuBarAutoHides,
                  screen.frame.maxY - screen.visibleFrame.maxY > 0 else { continue }
            seen.insert(id)
            let panel = panels[id] ?? makePanel()
            panels[id] = panel
            let barRect = ScreenGeometry.menuBarRect(on: screen)
            let shadowRoom: CGFloat = tint.shadow ? 14 : 0
            let frame = NSRect(x: barRect.minX, y: barRect.minY - shadowRoom, width: barRect.width, height: barRect.height + shadowRoom)
            panel.setFrame(frame, display: false)
            let isMenoScreen = screen == model.statusBar.screen
            let islands = isMenoScreen ? islandSpans(on: screen) : nil
            panel.contentView = NSHostingView(rootView: TintView(
                tint: tint,
                wallpaper: usesWallpaper ? wallpaper.reading(for: screen) : .pending,
                barHeight: barRect.height,
                shadowRoom: shadowRoom,
                islands: islands
            ))
            panel.orderFrontRegardless()
        }
        for (id, panel) in panels where !seen.contains(id) {
            panel.orderOut(nil)
            panels[id] = nil
        }
    }

    private func removeAll() {
        for panel in panels.values {
            panel.orderOut(nil)
        }
        panels.removeAll()
    }

    /// While the tint takes the wallpapers' colors, reads them when that
    /// begins, and again when the Space or the appearance changes and every
    /// few minutes, since a wallpaper can change without notice. Screens
    /// that change call ``screensChanged()``.
    private func watchWallpaper(_ watches: Bool) {
        guard watches else {
            wallpaperWatch?.cancel()
            wallpaperWatch = nil
            if let spaceObserver {
                NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
            }
            spaceObserver = nil
            appearanceObservation = nil
            return
        }
        guard wallpaperWatch == nil else { return }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshWallpaper()
            }
        }
        // Wallpapers with a light and a dark version change with it.
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.refreshWallpaper()
                }
            }
        }
        wallpaperWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300 * 1_000_000_000)
                self?.refreshWallpaper()
            }
        }
        refreshWallpaper()
    }

    private func refreshWallpaper() {
        wallpaper.refresh { [weak self] in
            guard let self, self.model.settings.tint.enabled, self.model.settings.tint.colorSource == .wallpaper else { return }
            self.update()
        }
    }

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel(level: NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1))
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        return panel
    }

    private func subscribeIfNeeded() {
        guard !subscribed else { return }
        subscribed = true
        model.inventory.$items
            .combineLatest(model.reveal.$appMenuFrame)
            .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.model.settings.tint.enabled, self.model.settings.tint.shape == .split else { return }
                    self.update()
                }
            }
            .store(in: &subscriptions)
    }

    /// Horizontal extents (relative to the screen) of the app menus and of
    /// the status items, for the split shape.
    private func islandSpans(on screen: NSScreen) -> TintView.Islands? {
        let screenRect = ScreenGeometry.quartzRect(fromCocoa: screen.frame)
        let frames = (model.inventory.items.map(\.frame) + model.statusBar.ownFrames)
            .filter { $0.width > 0 && screenRect.contains(CGPoint(x: $0.midX, y: $0.midY)) }
        guard let itemsMinX = frames.map(\.minX).min() else { return nil }
        let menusMaxX = model.reveal.appMenuFrame.map { $0.maxX - screenRect.minX } ?? 0
        return TintView.Islands(menusMaxX: menusMaxX, itemsMinX: itemsMinX - screenRect.minX, width: screenRect.width)
    }
}

struct TintView: View {
    struct Islands: Equatable {
        var menusMaxX: CGFloat
        var itemsMinX: CGFloat
        var width: CGFloat
    }

    let tint: MenuBarTint
    /// The colors of the wallpaper, when the tint takes them.
    let wallpaper: WallpaperReading
    let barHeight: CGFloat
    let shadowRoom: CGFloat
    let islands: Islands?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch tint.shape {
                case .full:
                    decorated(Rectangle())
                case .rounded:
                    decorated(RoundedRectangle(cornerRadius: (barHeight - 6) / 2, style: .continuous))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                case .split:
                    splitShapes
                }
            }
            .frame(height: barHeight)
            if shadowRoom > 0 {
                LinearGradient(colors: [Color.black.opacity(0.22), Color.black.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: shadowRoom)
                    .opacity(tint.shape == .full ? 1 : 0.6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var splitShapes: some View {
        let height = barHeight - 6
        let radius = height / 2
        if let islands {
            GeometryReader { proxy in
                let menusWidth = max(islands.menusMaxX + 10, 60)
                let itemsStart = max(islands.itemsMinX - 8, menusWidth + 8)
                decorated(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .frame(width: menusWidth - 6, height: height)
                    .position(x: 6 + (menusWidth - 6) / 2, y: proxy.size.height / 2)
                decorated(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .frame(width: max(proxy.size.width - itemsStart - 6, 20), height: height)
                    .position(x: itemsStart + max(proxy.size.width - itemsStart - 6, 20) / 2, y: proxy.size.height / 2)
            }
        } else {
            decorated(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
        }
    }

    private func decorated<S: Shape>(_ shape: S) -> some View {
        shape
            .fill(fillStyle)
            .overlay {
                if tint.border {
                    shape.stroke(tint.borderColor.color, lineWidth: CGFloat(tint.borderWidth))
                }
            }
    }

    private var fillStyle: AnyShapeStyle {
        let dark = colorScheme == .dark
        let chosen: (primary: RGBAColor, secondary: RGBAColor)?
        switch wallpaper {
        case .read(let palette):
            chosen = tint.colors(dark: dark, wallpaper: palette)
        case .unavailable:
            // A wallpaper that cannot be read, such as a moving one.
            chosen = tint.colors(dark: dark)
        case .pending:
            chosen = tint.colors(dark: dark, wallpaper: nil)
        }
        guard let colors = chosen else { return AnyShapeStyle(Color.clear) }
        switch tint.fill {
        case .solid:
            return AnyShapeStyle(colors.primary.color)
        case .gradient:
            return AnyShapeStyle(LinearGradient(
                colors: [colors.primary.color, colors.secondary.color],
                startPoint: .leading,
                endPoint: .trailing
            ))
        }
    }
}
