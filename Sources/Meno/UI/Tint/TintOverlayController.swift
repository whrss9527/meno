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

    init(model: AppModel) {
        self.model = model
    }

    func update() {
        let tint = model.settings.tint
        guard tint.enabled else {
            removeAll()
            return
        }
        subscribeIfNeeded()
        var seen = Set<CGDirectDisplayID>()
        for screen in NSScreen.screens {
            guard let id = ScreenGeometry.displayID(of: screen) else { continue }
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
    let barHeight: CGFloat
    let shadowRoom: CGFloat
    let islands: Islands?

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
        switch tint.fill {
        case .solid:
            return AnyShapeStyle(tint.color.color)
        case .gradient:
            return AnyShapeStyle(LinearGradient(
                colors: [tint.color.color, tint.secondaryColor.color],
                startPoint: .leading,
                endPoint: .trailing
            ))
        }
    }
}
