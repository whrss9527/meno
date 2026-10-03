import AppKit

/// Observes events sent to other apps. Handlers run on the main thread.
@MainActor
final class GlobalEventMonitor {
    private let mask: NSEvent.EventTypeMask
    private let handler: (NSEvent) -> Void
    private var token: Any?

    init(mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> Void) {
        self.mask = mask
        self.handler = handler
    }

    func start() {
        guard token == nil else { return }
        token = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handler(event)
            }
        }
    }

    func stop() {
        if let token {
            NSEvent.removeMonitor(token)
        }
        token = nil
    }
}

/// Observes events sent to Meno's own windows. The handler returns `true`
/// to consume an event.
@MainActor
final class LocalEventMonitor {
    private let mask: NSEvent.EventTypeMask
    private let handler: (NSEvent) -> Bool
    private var token: Any?

    init(mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> Bool) {
        self.mask = mask
        self.handler = handler
    }

    func start() {
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                self?.handler(event) ?? false
            }
            return consumed ? nil : event
        }
    }

    func stop() {
        if let token {
            NSEvent.removeMonitor(token)
        }
        token = nil
    }
}
