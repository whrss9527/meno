import AppKit
@preconcurrency import ApplicationServices

/// A running app whose menu bar items should be read.
struct ScanTarget: Sendable {
    let pid: pid_t
    let bundleID: String?
    let name: String
}

/// One menu bar item as reported by Accessibility.
struct RawMenuBarItem: @unchecked Sendable {
    let target: ScanTarget
    let element: AXUIElement
    let frame: CGRect
    let title: String?
    let detail: String?
    let identifier: String?
    let help: String?
}

/// Reads the menu bar items of all apps through each app's `AXExtrasMenuBar`.
///
/// This works on every supported macOS version, including macOS 27 where
/// the menu bar no longer uses one window per item.
enum MenuBarScanner {
    @MainActor
    static func currentTargets() -> [ScanTarget] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            let pid = app.processIdentifier
            guard !app.isTerminated, pid > 0, pid != AppInfo.ownPID else { return nil }
            let name = app.localizedName ?? app.bundleIdentifier ?? "PID \(pid)"
            return ScanTarget(pid: pid, bundleID: app.bundleIdentifier, name: name)
        }
    }

    /// Scans all targets concurrently, off the main thread.
    static func scan(_ targets: [ScanTarget]) async -> [RawMenuBarItem] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let collector = Collector()
                DispatchQueue.concurrentPerform(iterations: targets.count) { index in
                    collector.append(items(of: targets[index]))
                }
                continuation.resume(returning: collector.items)
            }
        }
    }

    static func items(of target: ScanTarget) -> [RawMenuBarItem] {
        let app = AXUIElementCreateApplication(target.pid)
        AX.setTimeout(app, seconds: 0.3)
        guard let bar = AX.element(app, AX.Attribute.extrasMenuBar) else { return [] }
        AX.setTimeout(bar, seconds: 0.3)
        return AX.elements(bar, AX.Attribute.children).compactMap { element in
            AX.setTimeout(element, seconds: 0.3)
            guard let frame = AX.frame(of: element) else { return nil }
            return RawMenuBarItem(
                target: target,
                element: element,
                frame: frame,
                title: AX.string(element, AX.Attribute.title),
                detail: AX.string(element, AX.Attribute.description),
                identifier: AX.string(element, AX.Attribute.identifier),
                help: AX.string(element, AX.Attribute.help)
            )
        }
    }

    /// Reads the description, title and help text of each element, or `nil`
    /// for an element that could not be read (for example a busy app).
    static func texts(of elements: [AXUIElement]) async -> [[String?]?] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let texts = elements.map { element -> [String?]? in
                    AX.setTimeout(element, seconds: 0.3)
                    let reads = [AX.Attribute.description, AX.Attribute.title, AX.Attribute.help].map {
                        AX.readString(element, $0)
                    }
                    guard reads.allSatisfy(\.readable) else { return nil }
                    return reads.map(\.text)
                }
                continuation.resume(returning: texts)
            }
        }
    }

    /// Reads the current frame of a single element.
    /// The current frames of elements, read off the main thread.
    static func frames(of elements: [AXUIElement]) async -> [CGRect?] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: elements.map { element in
                    AX.setTimeout(element, seconds: 0.3)
                    return AX.frame(of: element)
                })
            }
        }
    }

    static func frame(of element: AXUIElement) async -> CGRect? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                AX.setTimeout(element, seconds: 0.3)
                continuation.resume(returning: AX.frame(of: element))
            }
        }
    }

    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [RawMenuBarItem] = []

        func append(_ new: [RawMenuBarItem]) {
            guard !new.isEmpty else { return }
            lock.lock()
            storage.append(contentsOf: new)
            lock.unlock()
        }

        var items: [RawMenuBarItem] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
    }
}

/// Reads the extent of an app's own menus (File, Edit, …).
enum AppMenuInspector {
    static func menuFrame(ofPID pid: pid_t) async -> CGRect? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let app = AXUIElementCreateApplication(pid)
                AX.setTimeout(app, seconds: 0.25)
                guard let bar = AX.element(app, AX.Attribute.menuBar) else {
                    continuation.resume(returning: nil)
                    return
                }
                let frames = AX.elements(bar, AX.Attribute.children)
                    .compactMap { AX.frame(of: $0) }
                    .filter { $0.width > 0 && $0.height > 0 }
                let union = frames.dropFirst().reduce(frames.first) { partial, frame in
                    partial?.union(frame)
                }
                continuation.resume(returning: union)
            }
        }
    }
}
