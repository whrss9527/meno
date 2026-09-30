import AppKit
import SwiftUI

/// Short glass notifications below the menu bar.
@MainActor
final class ToastCenter: ObservableObject {
    struct Action: Identifiable {
        let id = UUID()
        let title: String
        let handler: () -> Void
    }

    struct Toast: Identifiable {
        let id = UUID()
        let message: String
        let symbol: String
        let actions: [Action]
    }

    @Published private(set) var current: Toast?

    private var panel: FloatingPanel?
    private var hostingView: NSHostingView<ToastView>?
    private var hiding = false
    private var dismissTask: Task<Void, Never>?

    /// Where toasts appear; set by the app model.
    var screenProvider: () -> NSScreen? = { NSScreen.main }

    func show(_ message: String, symbol: String = "info.circle.fill", actions: [Action] = [], duration: TimeInterval? = nil) {
        let toast = Toast(message: message, symbol: symbol, actions: actions)
        current = toast
        hiding = false
        let panel = self.panel ?? makePanel()
        hostingView?.rootView = ToastView(toast: toast, center: self)
        panel.ignoresMouseEvents = actions.isEmpty
        // With VoiceOver, a notice with actions takes the focus, so that its
        // buttons can be reached, and stays until it is dealt with.
        let reachable = !actions.isEmpty && NSWorkspace.shared.isVoiceOverEnabled
        panel.allowsKey = reachable
        layout()
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        if reachable {
            panel.makeKey()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
        let announcement = actions.isEmpty
            ? message
            : String(localized: "\(message) Actions: \(ListFormatter.localizedString(byJoining: actions.map(\.title))).")
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: announcement,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
        dismissTask?.cancel()
        let seconds = reachable ? max(duration ?? 0, 60) : duration ?? (actions.isEmpty ? 2.6 : 8)
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        guard let panel, current != nil else { return }
        hiding = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                guard self.hiding else { return }
                panel.orderOut(nil)
                self.current = nil
            }
        })
    }

    func perform(_ action: Action) {
        dismiss()
        action.handler()
    }

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel(level: .statusBar)
        let view = FirstMouseHostingView(rootView: ToastView(toast: nil, center: self))
        panel.contentView = view
        self.panel = panel
        hostingView = view
        return panel
    }

    private func layout() {
        guard let panel, let hostingView else { return }
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        guard let screen = screenProvider() ?? NSScreen.screens.first else { return }
        let top = screen.frame.maxY - ScreenGeometry.menuBarHeight(on: screen) - 8
        panel.setFrame(
            NSRect(x: screen.frame.midX - size.width / 2, y: top - size.height, width: size.width, height: size.height),
            display: true
        )
    }
}

struct ToastView: View {
    let toast: ToastCenter.Toast?
    let center: ToastCenter

    var body: some View {
        if let toast {
            HStack(spacing: 10) {
                Image(systemName: toast.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(verbatim: toast.message)
                    .font(.system(size: 13, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 420, alignment: .leading)
                ForEach(toast.actions) { action in
                    Button(action.title) {
                        center.perform(action)
                    }
                    .controlSize(.small)
                    .menoGlassButtonStyle(prominent: action.id == toast.actions.first?.id)
                }
                if !toast.actions.isEmpty {
                    Button {
                        center.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Close"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            // Escape dismisses a notice that took the focus.
            .onExitCommand { center.dismiss() }
            .menoGlass(in: Capsule())
            .padding(16)
            .fixedSize()
        } else {
            Color.clear.frame(width: 1, height: 1)
        }
    }
}
