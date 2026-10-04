import Foundation

/// A loopback release endpoint for testing real downloads without GitHub.
/// It changes the source, never the installer signature or bundle checks.
public struct UpdateSource: Equatable, Sendable {
    public let latestURL: URL

    public init?(override: String?) {
        guard let override, let url = URL(string: override),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              ["localhost", "127.0.0.1", "[::1]", "::1"].contains(url.host?.lowercased() ?? ""),
              url.user == nil, url.password == nil else { return nil }
        latestURL = url
    }

    public func accepts(_ url: URL) -> Bool {
        url.scheme?.lowercased() == latestURL.scheme?.lowercased()
            && url.host?.lowercased() == latestURL.host?.lowercased()
            && url.port == latestURL.port && url.user == nil && url.password == nil
    }
}
