import Foundation

/// A dotted version such as `0.2.1`, for telling whether a release is newer.
///
/// A leading `v` and anything after `-` or `+` are ignored, and missing
/// parts count as zero, so `v1.2` equals `1.2.0`.
public struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    public let components: [Int]

    public init?(_ text: String) {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.first == "v" || trimmed.first == "V" {
            trimmed.removeFirst()
        }
        guard let core = trimmed.split(whereSeparator: { $0 == "-" || $0 == "+" }).first else { return nil }
        let parts = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ ($0 ?? -1) >= 0 }) else { return nil }
        components = parts.compactMap { $0 }
    }

    public var description: String {
        components.map(String.init).joined(separator: ".")
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}
