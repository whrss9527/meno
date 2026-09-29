import AppKit

enum AppInfo {
    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "io.github.whrss9527.meno"
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    static var osMajorVersion: Int {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    }

    static var osVersionString: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    /// Liquid Glass is available when running on macOS 26 or later with an
    /// SDK that has it.
    static var hasLiquidGlass: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { return true }
        #endif
        return false
    }

    static let ownPID = ProcessInfo.processInfo.processIdentifier

    static let repositoryURL = URL(string: "https://github.com/whrss9527/meno")!

    /// Whether Meno runs from an app bundle (as opposed to `swift run`).
    static var isBundled: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }
}
