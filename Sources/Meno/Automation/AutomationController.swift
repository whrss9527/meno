import AppKit
import MenoCore
import Network

/// Runs the user's rules: "when these conditions are true, do this".
@MainActor
final class AutomationController: ObservableObject {
    unowned let model: AppModel

    @Published private(set) var context = RuleContext()
    @Published private(set) var activeRuleIDs: Set<UUID> = []
    /// Microphone and camera use, while a rule watches it.
    private(set) var capture = CaptureActivity.State()

    private var evaluator = RuleEvaluator()
    private var observers: [NSObjectProtocol] = []
    private var pathMonitor: NWPathMonitor?
    private var isOnline = true
    private var loopTask: Task<Void, Never>?
    private(set) var watchesCaptureActivity = false
    private lazy var captureActivity = CaptureActivity { [weak self] state in
        MainActor.assumeIsolated {
            guard let self else { return }
            self.capture = state
            self.evaluate()
        }
    }
    /// The commands of rule conditions that succeeded when they last ran.
    private(set) var succeededCommands: Set<String> = []
    private lazy var commandChecks = CommandChecks { [weak self] succeeded in
        MainActor.assumeIsolated {
            guard let self else { return }
            self.succeededCommands = succeeded
            self.evaluate()
        }
    }

    /// Work to undo when a rule stops applying.
    private struct Undo {
        /// Always runs (for example releasing a hold).
        var cleanup: () -> Void = {}
        /// Runs only if the rule reverts its action.
        var revert: () -> Void = {}
    }

    private var undo: [UUID: Undo] = [:]

    init(model: AppModel) {
        self.model = model
    }

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        let names = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didWakeNotification,
        ]
        for name in names {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.evaluate()
                }
            })
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.evaluate()
            }
        })

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self, self.isOnline != online else { return }
                self.isOnline = online
                self.evaluate()
            }
        }
        monitor.start(queue: DispatchQueue(label: "\(AppInfo.bundleIdentifier).network"))
        pathMonitor = monitor

        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                self?.evaluate()
            }
        }
        watchCaptureActivity()
        commandChecks.watch(model.settings.rules.commands)
        evaluate()
    }

    func rulesChanged() {
        let ids = Set(model.settings.rules.map(\.id))
        // Rules that were deleted while active clean up without reverting.
        for (id, entry) in undo where !ids.contains(id) {
            entry.cleanup()
            undo[id] = nil
        }
        watchCaptureActivity()
        commandChecks.watch(model.settings.rules.commands)
        evaluate()
    }

    /// Microphones and cameras are only watched while an enabled rule
    /// depends on them.
    private func watchCaptureActivity() {
        let conditions = model.settings.rules.filter(\.isEnabled).flatMap(\.conditions)
        let microphones = conditions.contains(.microphoneInUse)
        let cameras = conditions.contains(.cameraInUse)
        guard microphones || cameras || watchesCaptureActivity else { return }
        watchesCaptureActivity = microphones || cameras
        captureActivity.watch(microphones: microphones, cameras: cameras)
    }

    func evaluate() {
        context = SystemSignals.snapshot(isOnline: isOnline, capture: capture, succeededCommands: succeededCommands)
        let transitions = evaluator.update(rules: model.settings.rules, context: context)
        activeRuleIDs = evaluator.activeRuleIDs
        for transition in transitions {
            switch transition {
            case .activated(let rule): activate(rule)
            case .deactivated(let rule): deactivate(rule)
            }
        }
    }

    private func activate(_ rule: AutomationRule) {
        Log.rules.info("Rule activated: \(rule.name, privacy: .public)")
        let reveal = model.reveal
        switch rule.action {
        case .revealHidden, .revealAll:
            reveal.reveal(all: rule.action == .revealAll, trigger: .rule)
            reveal.hold()
            undo[rule.id] = Undo(cleanup: { reveal.release() }, revert: { reveal.collapse(trigger: .rule) })
        case .collapse:
            reveal.collapse(trigger: .rule)
        case .zen:
            let wasActive = model.isZenActive
            model.setZen(true, announce: false)
            undo[rule.id] = Undo(revert: { [weak model = self.model] in
                if !wasActive { model?.setZen(false, announce: false) }
            })
        case .applyScene(let id):
            guard let scene = model.settings.scenes.first(where: { $0.id == id }) else { return }
            let previous = model.inventory.currentLayout()
            Task { await model.applyScene(scene, automatic: true) }
            undo[rule.id] = Undo(revert: { [weak model = self.model] in
                Task { try? await model?.mover.apply(previous, automatic: true) }
            })
        case .showItem(let key), .hideItem(let key), .stashItem(let key):
            guard let target = rule.action.targetSection else { return }
            let original = model.inventory.item(for: key)?.section
            Task { [weak model = self.model] in
                do {
                    try await model?.mover.move(key, to: target, automatic: true)
                } catch {
                    Log.rules.error("Rule move failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            if let original, original != target {
                undo[rule.id] = Undo(revert: { [weak model = self.model] in
                    Task { try? await model?.mover.move(key, to: original, automatic: true) }
                })
            }
        }
    }

    private func deactivate(_ rule: AutomationRule) {
        Log.rules.info("Rule deactivated: \(rule.name, privacy: .public)")
        guard let entry = undo.removeValue(forKey: rule.id) else { return }
        entry.cleanup()
        if rule.revertsWhenInactive {
            entry.revert()
        }
    }
}
