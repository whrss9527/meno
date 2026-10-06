import Foundation

/// Opens the issue form with the version details that help reproduce a report.
public enum FeedbackLink {
    public static func bugReport(repositoryURL: URL, version: String, systemVersion: String) -> URL {
        var components = URLComponents(url: repositoryURL.appendingPathComponent("issues/new"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "template", value: "bug.yml"),
            URLQueryItem(name: "version", value: "Meno \(version); macOS \(systemVersion)"),
        ]
        return components.url!
    }
}
