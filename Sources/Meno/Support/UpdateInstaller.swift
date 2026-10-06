import AppKit
import CoreServices
import CryptoKit
import MenoCore
import Security

/// Puts a newer release in place of the running copy of Meno.
///
/// The release's zip is downloaded from GitHub and checked before anything
/// is replaced: its size when provided and a required checksum, the bundle
/// identifier and version, that it runs on this Mac, and a valid code
/// signature, from the same certificate when this copy has one. The two
/// copies then swap places. The previous copy is deleted by the new one
/// once it started, and put back when the new one cannot be opened.
enum UpdateInstaller {
    enum Failure: LocalizedError {
        case notBundled
        case translocated
        case readOnly
        case noArchive
        case download
        case damaged
        case noChecksum
        case unexpectedApp
        case invalidSignature
        case differentSigner
        case needsNewerMacOS(String)
        case otherProcessor

        var errorDescription: String? {
            switch self {
            case .notBundled:
                return String(localized: "This copy of Meno does not run from an app bundle.")
            case .translocated:
                return String(localized: "macOS runs Meno from a temporary copy. Move Meno to the Applications folder, open it from there and try again.")
            case .readOnly:
                return String(localized: "Meno cannot replace itself in its folder.")
            case .noArchive:
                return String(localized: "The release has no app to install.")
            case .download:
                return String(localized: "The download failed.")
            case .noChecksum:
                return String(localized: "The release has no usable checksum. Meno cannot verify the download.")
            case .damaged:
                return String(localized: "The download is incomplete or damaged.")
            case .unexpectedApp:
                return String(localized: "The download is not the expected version of Meno.")
            case .invalidSignature:
                return String(localized: "The download's code signature is not valid.")
            case .differentSigner:
                return String(localized: "The download is signed differently than this copy of Meno.")
            case .needsNewerMacOS(let version):
                return String(localized: "This version needs macOS \(version) or later.")
            case .otherProcessor:
                return String(localized: "This version does not run on this Mac's processor.")
            }
        }
    }

    /// A checked release, ready to replace this copy.
    struct Prepared {
        let app: URL
        /// Holds the download and, once replaced, the previous copy.
        let folder: URL
    }

    /// Where the new copy finds what to delete once it started.
    private static let leftoversKey = "UpdateLeftovers"

    /// Why Meno cannot replace itself where it runs, if it cannot.
    static var blocker: Failure? {
        guard AppInfo.isBundled else { return .notBundled }
        let bundle = Bundle.main.bundleURL
        // Apps opened from a quarantined download run from a read-only copy.
        if bundle.path.contains("/AppTranslocation/") { return .translocated }
        let fileManager = FileManager.default
        guard fileManager.isWritableFile(atPath: bundle.deletingLastPathComponent().path),
              fileManager.isWritableFile(atPath: bundle.path)
        else { return .readOnly }
        return nil
    }

    /// Downloads, unpacks and checks the app of `release`.
    static func prepare(_ release: UpdateRelease, repository: String, source: UpdateSource? = nil) async throws -> Prepared {
        if let blocker { throw blocker }
        guard let version = release.version, let archive = release.appArchive(repository: repository, source: source) else {
            throw Failure.noArchive
        }
        let fileManager = FileManager.default
        // On the same volume as the app, so it can be swapped in one step.
        // A private sibling remains writable across the two app processes.
        // A system-managed replacement directory can deny deletion after relaunch.
        let folder = Bundle.main.bundleURL.deletingLastPathComponent()
            .appendingPathComponent(".Meno-update-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: false,
                                        attributes: [.posixPermissions: 0o700])
        do {
            let zip = folder.appendingPathComponent("Meno.zip")
            let checksum = try await expectedChecksum(archive, release: release, repository: repository, source: source)
            try await download(archive, to: zip, checksum: checksum)
            let unpacked = folder.appendingPathComponent("Unpacked", isDirectory: true)
            guard await run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path]) == 0 else {
                throw Failure.damaged
            }
            let app = try findApp(in: unpacked)
            try check(app, version: version)
            releaseFromQuarantine(app)
            return Prepared(app: app, folder: folder)
        } catch {
            try? fileManager.removeItem(at: folder)
            throw error
        }
    }

    /// Puts the prepared copy in place of this one and returns where this
    /// one went. The new copy deletes it once it started.
    static func replace(with prepared: Prepared) throws -> URL {
        let bundle = Bundle.main.bundleURL
        let previous: URL
        // Swapped in one step where the volume allows it, so that there is
        // always a copy of Meno in its place.
        if renamex_np(prepared.app.path, bundle.path, UInt32(RENAME_SWAP)) == 0 {
            previous = prepared.app
        } else {
            let fileManager = FileManager.default
            previous = prepared.folder.appendingPathComponent("Previous.app", isDirectory: true)
            try fileManager.moveItem(at: bundle, to: previous)
            do {
                try fileManager.moveItem(at: prepared.app, to: bundle)
            } catch {
                // Without this, the only copy would be deleted with the folder.
                try fileManager.moveItem(at: previous, to: bundle)
                throw error
            }
        }
        LSRegisterURL(bundle as CFURL, true)
        UserDefaults.standard.set(prepared.folder.path, forKey: leftoversKey)
        return previous
    }

    /// Deletes the download of an update that was not installed, unless
    /// the folder holds the only copy of Meno.
    static func discard(_ prepared: Prepared) {
        let bundle = Bundle.main.bundleURL
        guard FileManager.default.fileExists(atPath: bundle.appendingPathComponent("Contents/Info.plist").path),
              !bundle.path.hasPrefix(prepared.folder.path)
        else {
            Log.app.fault("Keeping \(prepared.folder.path, privacy: .public): Meno is not in its place")
            return
        }
        try? FileManager.default.removeItem(at: prepared.folder)
    }

    /// Deletes what an update left behind once Meno has run for a few
    /// seconds: the download and the previous copy. Until then the previous
    /// copy is put back if this one quits. Returns the version of a new copy
    /// that did not run and was replaced by this one again, if any.
    @MainActor
    static func removeLeftovers() -> String? {
        let defaults = UserDefaults.standard
        guard let path = defaults.string(forKey: leftoversKey) else { return nil }
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: folder.path) else {
            defaults.removeObject(forKey: leftoversKey)
            return nil
        }
        // Only a folder made for an update, never one Meno runs from.
        guard fileManager.fileExists(atPath: folder.appendingPathComponent("Meno.zip").path),
              !Bundle.main.bundlePath.hasPrefix(folder.path)
        else {
            Diagnostics.event("update_cleanup skipped folder=\(folder.path) bundle=\(Bundle.main.bundlePath)")
            return nil
        }
        let rejected = [
            folder.appendingPathComponent("Unpacked/Meno.app.rejected"),
            folder.appendingPathComponent("Previous.app.rejected"),
        ].first { fileManager.fileExists(atPath: $0.path) }
        let version = rejected.flatMap {
            NSDictionary(contentsOf: $0.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String
        }
        do {
            try fileManager.removeItem(at: folder)
            defaults.removeObject(forKey: leftoversKey)
        } catch {
            Log.app.error("Update cleanup failed: \(error.localizedDescription, privacy: .public)")
            Diagnostics.event("update_cleanup failed error=\(error.localizedDescription)")
            return nil
        }
        return version
    }

    private static func expectedChecksum(_ archive: UpdateRelease.Asset, release: UpdateRelease,
                                         repository: String, source: UpdateSource?) async throws -> String {
        if let digest = archive.sha256 { return digest }
        guard let asset = release.checksumArchive(repository: repository, source: source) else {
            throw Failure.noChecksum
        }
        var request = URLRequest(url: asset.downloadURL, timeoutInterval: 30)
        request.setValue("Meno/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        let data: Data
        do {
            let result = try await URLSession.shared.data(for: request)
            guard (result.1 as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.noChecksum }
            data = result.0
        } catch is CancellationError { throw CancellationError() }
        catch { throw Failure.noChecksum }
        guard let text = String(data: data, encoding: .utf8),
              let checksum = try? UpdateRelease.expectedSHA256(for: archive, checksums: text) else {
            throw Failure.noChecksum
        }
        return checksum
    }

    private static func download(_ asset: UpdateRelease.Asset, to destination: URL, checksum: String) async throws {
        var request = URLRequest(url: asset.downloadURL, timeoutInterval: 60)
        request.setValue("Meno/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        let result: (URL, URLResponse)
        do {
            result = try await URLSession.shared.download(for: request)
        } catch {
            Log.app.error("Update download failed: \(error.localizedDescription, privacy: .public)")
            throw Failure.download
        }
        let (file, response) = result
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            try? FileManager.default.removeItem(at: file)
            throw Failure.download
        }
        try FileManager.default.moveItem(at: file, to: destination)
        let data = try Data(contentsOf: destination, options: .mappedIfSafe)
        if let size = asset.size, data.count != size {
            throw Failure.damaged
        }
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == checksum else { throw Failure.damaged }
    }

    private static func findApp(in folder: URL) throws -> URL {
        let expected = folder.appendingPathComponent("Meno.app", isDirectory: true)
        if FileManager.default.fileExists(atPath: expected.path) { return expected }
        let contents = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        guard let app = contents.first(where: { $0.pathExtension == "app" }) else { throw Failure.damaged }
        return app
    }

    private static func check(_ app: URL, version: AppVersion) throws {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: plist) as? [String: Any],
              info["CFBundleIdentifier"] as? String == AppInfo.bundleIdentifier,
              let text = info["CFBundleShortVersionString"] as? String,
              AppVersion(text) == version
        else { throw Failure.unexpectedApp }

        // It has to run here, or the swap would leave a copy that cannot open.
        if let minimum = info["LSMinimumSystemVersion"] as? String,
           let required = AppVersion(minimum),
           let running = AppVersion(AppInfo.osVersionString),
           running < required {
            throw Failure.needsNewerMacOS(minimum)
        }
        let architectures = Bundle(url: app)?.executableArchitectures?.map(\.intValue) ?? []
        guard architectures.contains(hostArchitecture) else { throw Failure.otherProcessor }

        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else {
            throw Failure.invalidSignature
        }
        let flags = SecCSFlags(rawValue:
            UInt32(kSecCSCheckAllArchitectures) | UInt32(kSecCSCheckNestedCode) | UInt32(kSecCSStrictValidate)
        )
        guard SecStaticCodeCheckValidityWithErrors(code, flags, nil, nil) == errSecSuccess else {
            throw Failure.invalidSignature
        }
        if let requirement = CodeSigning.requirementForUpdates,
           SecStaticCodeCheckValidityWithErrors(code, flags, requirement, nil) != errSecSuccess {
            throw Failure.differentSigner
        }
        guard CodeSigning.identifier(of: code) == AppInfo.bundleIdentifier else {
            throw Failure.unexpectedApp
        }
    }

    /// The architecture this copy runs as.
    private static var hostArchitecture: Int {
        #if arch(arm64)
        return NSBundleExecutableArchitectureARM64
        #else
        return NSBundleExecutableArchitectureX86_64
        #endif
    }

    /// Downloads made by Meno are not quarantined, but an archive that was
    /// would pass it on. The person chose to install this checked copy, so it
    /// should open without Gatekeeper asking again.
    private static func releaseFromQuarantine(_ app: URL) {
        let attribute = "com.apple.quarantine"
        removexattr(app.path, attribute, XATTR_NOFOLLOW)
        guard let enumerator = FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil) else { return }
        for case let url as URL in enumerator {
            removexattr(url.path, attribute, XATTR_NOFOLLOW)
        }
    }

    private static func run(_ path: String, _ arguments: [String]) async -> Int32 {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { process in
                continuation.resume(returning: process.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: -1)
            }
        }
    }
}
