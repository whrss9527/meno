import AppKit
import SwiftUI

// MARK: - Glass surfaces

extension View {
    /// Liquid Glass on macOS 26 and later; a frosted material with a light
    /// rim on earlier versions.
    @ViewBuilder
    func menoGlass<S: Shape>(
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false,
        clear: Bool = false
    ) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffect(liquidGlass(tint: tint, interactive: interactive, clear: clear), in: shape)
        } else {
            self.modifier(FrostedGlass(shape: shape, tint: tint, clear: clear))
        }
        #else
        self.modifier(FrostedGlass(shape: shape, tint: tint, clear: clear))
        #endif
    }

    /// A rounded glass card.
    func menoGlassCard(cornerRadius: CGFloat = 18, tint: Color? = nil) -> some View {
        menoGlass(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), tint: tint)
    }

    /// Glass buttons on macOS 26 and later, frosted capsules otherwise.
    @ViewBuilder
    func menoGlassButtonStyle(prominent: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            self.buttonStyle(FrostedButtonStyle(prominent: prominent))
        }
        #else
        self.buttonStyle(FrostedButtonStyle(prominent: prominent))
        #endif
    }
}

#if compiler(>=6.2)
@available(macOS 26.0, *)
private func liquidGlass(tint: Color?, interactive: Bool, clear: Bool) -> Glass {
    var glass: Glass = clear ? .clear : .regular
    if let tint {
        glass = glass.tint(tint)
    }
    if interactive {
        glass = glass.interactive()
    }
    return glass
}
#endif

/// Groups glass shapes so they blend and morph into each other.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
        #else
        content()
        #endif
    }
}

/// The pre-Liquid Glass look: blur, a soft highlight and a hairline rim.
struct FrostedGlass<S: Shape>: ViewModifier {
    let shape: S
    var tint: Color?
    var clear: Bool

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let dark = colorScheme == .dark
        content
            .background {
                ZStack {
                    shape.fill(clear ? Material.ultraThinMaterial : Material.thinMaterial)
                    if let tint {
                        shape.fill(tint.opacity(0.18))
                    }
                    shape.fill(
                        LinearGradient(
                            colors: [Color.white.opacity(dark ? 0.10 : 0.32), Color.white.opacity(0)],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                }
            }
            .overlay {
                shape.stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(dark ? 0.38 : 0.8),
                            Color.white.opacity(0.06),
                            Color.white.opacity(dark ? 0.16 : 0.4),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            }
            .shadow(color: Color.black.opacity(dark ? 0.32 : 0.12), radius: 14, x: 0, y: 8)
    }
}

struct FrostedButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background {
                Capsule().fill(prominent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Material.thinMaterial))
            }
            .overlay {
                Capsule().stroke(Color.white.opacity(prominent ? 0.25 : 0.45), lineWidth: 0.8)
            }
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Backdrops

/// An `NSVisualEffectView` for window backgrounds.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blending: NSVisualEffectView.BlendingMode = .behindWindow
    var cornerRadius: CGFloat = 0

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
        view.maskImage = cornerRadius > 0 ? Self.mask(radius: cornerRadius) : nil
    }

    private static func mask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// Soft color fields behind glass, so the glass has something to refract.
struct AuroraBackground: View {
    var intensity: Double = 1

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                blob(Color(red: 0.36, green: 0.47, blue: 1.00), x: 0.12, y: 0.08, scale: 0.95, in: size)
                blob(Color(red: 0.80, green: 0.38, blue: 0.96), x: 0.88, y: 0.22, scale: 0.8, in: size)
                blob(Color(red: 0.18, green: 0.78, blue: 0.86), x: 0.60, y: 0.96, scale: 1.05, in: size)
                blob(Color(red: 1.00, green: 0.62, blue: 0.42), x: 0.04, y: 0.86, scale: 0.6, in: size)
            }
            .blur(radius: 80)
            .opacity((colorScheme == .dark ? 0.42 : 0.30) * intensity)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func blob(_ color: Color, x: CGFloat, y: CGFloat, scale: CGFloat, in size: CGSize) -> some View {
        let diameter = max(size.width, size.height) * 0.6 * scale
        return Circle()
            .fill(color)
            .frame(width: diameter, height: diameter)
            .position(x: size.width * x, y: size.height * y)
    }
}

// MARK: - Panels

/// A hosting view that reacts to the first click, even while its panel is
/// not key, so buttons in glass panels work with a single click.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

/// A borderless, transparent, non-activating panel for glass overlays.
final class FloatingPanel: NSPanel {
    /// Whether the panel may become key (needed for text input).
    var allowsKey = false

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
    }

    convenience init(level: NSWindow.Level = .statusBar) {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.level = level
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}
