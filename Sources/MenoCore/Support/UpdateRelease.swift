import Foundation

/// A release on GitHub, as far as updating Meno needs it.
public struct UpdateRelease: Decodable, Equatable, Sendable {
    public struct Asset: Decodable, Equatable, Sendable {
        public let name: String
        public let downloadURL: URL
        /// The size in bytes.
        public let size: Int?
        /// The checksum GitHub gives for newer uploads, for example `sha256:…`.
        public let digest: String?

        public init(name: String, downloadURL: URL, size: Int? = nil, digest: String? = nil) {
            self.name = name
            self.downloadURL = downloadURL
            self.size = size
            self.digest = digest
        }

        enum CodingKeys: String, CodingKey {
            case name
            case downloadURL = "browser_download_url"
            case size
            case digest
        }

        /// The SHA-256 checksum as lowercase hex, if GitHub gave one.
        public var sha256: String? {
            guard let digest else { return nil }
            let prefix = "sha256:"
            guard digest.lowercased().hasPrefix(prefix) else { return nil }
            let hex = digest.dropFirst(prefix.count).lowercased()
            guard hex.count == 64, hex.allSatisfy(\.isHexDigit) else { return nil }
            return String(hex)
        }
    }

    public let tagName: String
    public let htmlURL: URL
    public let assets: [Asset]

    public init(tagName: String, htmlURL: URL, assets: [Asset] = []) {
        self.tagName = tagName
        self.htmlURL = htmlURL
        self.assets = assets
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tagName = try container.decode(String.self, forKey: .tagName)
        htmlURL = try container.decode(URL.self, forKey: .htmlURL)
        assets = (try? container.decodeIfPresent([Asset].self, forKey: .assets)) ?? []
    }

    public var version: AppVersion? {
        AppVersion(tagName)
    }

    /// The zipped app to install, if the release has one that was published
    /// with this release of `repository` (for example `owner/name`).
    public func appArchive(repository: String) -> Asset? {
        let candidates = assets.filter { Self.isDownload($0.downloadURL, of: tagName, in: repository) }
        return candidates.first { $0.name == "Meno.zip" }
            ?? candidates.first { $0.name.hasPrefix("Meno") && $0.name.hasSuffix(".zip") }
    }

    /// Whether `url` is a file attached to the release `tag` of `repository`
    /// on GitHub, fetched over HTTPS.
    static func isDownload(_ url: URL, of tag: String, in repository: String) -> Bool {
        guard url.scheme?.lowercased() == "https", url.host?.lowercased() == "github.com" else { return false }
        let prefix = "/\(repository)/releases/download/\(tag)/"
        return url.path.hasPrefix(prefix) && url.path.count > prefix.count && !url.path.contains("/../")
    }
}
