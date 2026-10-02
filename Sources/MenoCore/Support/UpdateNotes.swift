import Foundation

/// What changed in every version after the running one, up to a newer
/// release, taken from the notes of the releases on GitHub.
///
/// The notes of a release are written in English and then in Chinese, after
/// a `---` line. Only the part in the interface's language is kept, without
/// the sections that every release repeats, such as how to install it.
public struct UpdateNotes: Equatable, Sendable {
    /// How many releases to ask GitHub for at once, its maximum.
    public static let pageSize = 100

    public struct Version: Equatable, Sendable {
        public let version: AppVersion
        public let date: Date?
        public let blocks: [Block]
    }

    /// A part of a version's notes. The text may hold inline Markdown, such
    /// as `**bold**` or `` `code` ``.
    public enum Block: Equatable, Sendable {
        case heading(String)
        case item(String)
        case paragraph(String)
    }

    /// The tag of the release the notes lead up to.
    public let tagName: String
    /// Newest first.
    public let versions: [Version]
    /// Whether every version after the running one is listed. If not, the
    /// list of releases could not be read or does not reach back that far.
    public let isComplete: Bool

    /// Sections every release repeats, by their heading in lowercase.
    static let repeatedSections: Set<String> = [
        "install", "install or update", "known limitations",
        "安装", "安装与更新", "已知限制",
    ]
    /// Lines that only point to the other language.
    static let pointers: Set<String> = ["中文说明见下方。"]

    /// - Parameters:
    ///   - current: The version that runs.
    ///   - latest: The newer release that was found.
    ///   - releases: The newest releases, as GitHub lists them, or `nil`
    ///     when they could not be read. Then only `latest` is listed.
    ///   - chinese: Whether to keep the Chinese part of the notes rather
    ///     than the English one.
    public init(current: AppVersion, latest: UpdateRelease, releases: [UpdateRelease]?, chinese: Bool) {
        let newest = latest.version
        func isListed(_ version: AppVersion) -> Bool {
            guard current < version else { return false }
            guard let newest else { return true }
            return !(newest < version)
        }
        var versions: [Version] = []
        for release in [latest] + (releases ?? []) where !release.isDraft && !release.isPrerelease {
            guard let version = release.version, isListed(version), !versions.contains(where: { $0.version == version }) else {
                continue
            }
            versions.append(Version(
                version: version,
                date: release.publishedAt,
                blocks: Self.blocks(of: release.body ?? "", chinese: chinese)
            ))
        }
        tagName = latest.tagName
        self.versions = versions.sorted { $1.version < $0.version }
        if let releases {
            // A list shorter than a page holds every release; otherwise it
            // has to reach the running version.
            isComplete = releases.count < Self.pageSize
                || releases.contains { $0.version.map { !(current < $0) } ?? false }
        } else {
            isComplete = false
        }
    }

    /// The headings, list items and paragraphs of a release's notes.
    static func blocks(of body: String, chinese: Bool) -> [Block] {
        let lines = body.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var part = lines[...]
        if let rule = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            part = chinese ? lines[(rule + 1)...] : lines[..<rule]
        }
        var blocks: [Block] = []
        var skipping = false
        var afterBlank = true
        for raw in part {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                afterBlank = true
                continue
            }
            let continues = !afterBlank
            afterBlank = false
            if line.hasPrefix("#") {
                let title = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                skipping = repeatedSections.contains(title.lowercased())
                if !skipping, !title.isEmpty {
                    blocks.append(.heading(title))
                }
                continue
            }
            if skipping || pointers.contains(line) { continue }
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                blocks.append(.item(line.dropFirst(2).trimmingCharacters(in: .whitespaces)))
                continue
            }
            // A line right below another one carries on its item or paragraph.
            switch blocks.last {
            case .item(let text)? where continues:
                blocks[blocks.count - 1] = .item(text + " " + line)
            case .paragraph(let text)? where continues:
                blocks[blocks.count - 1] = .paragraph(text + " " + line)
            default:
                blocks.append(.paragraph(line))
            }
        }
        return blocks
    }
}
