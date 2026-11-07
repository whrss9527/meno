import Foundation

/// Pure geometry for the palette, shared by the controller and boundary tests.
public enum QuickOpenGeometry {
    public static func frame(preferredSize: CGSize, in available: CGRect) -> CGRect {
        guard available.width > 0, available.height > 0 else { return .zero }
        let size = CGSize(width: min(max(0, preferredSize.width), available.width),
                          height: min(max(0, preferredSize.height), available.height))
        let preferredY = available.maxY - available.height * 0.2 - size.height
        return CGRect(x: available.midX - size.width / 2,
                      y: min(max(preferredY, available.minY), available.maxY - size.height),
                      width: size.width, height: size.height)
    }

    public static func contentSize(in available: CGSize) -> CGSize {
        CGSize(width: min(600, max(0, available.width - 48)), height: max(0, available.height - 48))
    }
}
