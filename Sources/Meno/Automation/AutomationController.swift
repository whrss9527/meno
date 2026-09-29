import AppKit
import IOKit.ps
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

    /// Where things were before a rule moved them, for its revert.
    @MainActor
    private final class Snapshot {
        var section: ItemSection?
        var layout: SceneLayout?
    }

    /// What an active rule did, and how to undo it.
    private struct Applied {
        var action: RuleAction
        /// Always runs (for example releasing a hold).
        var cleanup: () -> Void = {}
        /// Runs only if the rule reverts its action.
        var revert: () -> Void = {}
    }

    /// A revert that has not moved everything back yet.
    private struct PendingRevert {
        var action: RuleAction
        var snapshot: Snapshot
        var task: Task<Void, Never>
        var token: UUID
    }

    private var applied: [UUID: Applied] = [:]
    /// Moves a rule is waiting to make (moves wait until the mouse and
    /// keyboard are idle), so they can be called off.
    private var pendingMoves: [UUID: Task<Void, Never>] = [:]
    private var pendingReverts: [UUID: PendingRevert] = [:]
    /// Active rules that show items or turn on Zen. The last one to stop
    /// undoes it, and Zen stays on if it was on before.
    private var revealRules: Set<UUID> = []
    private var zenRules: Set<UUID> = []
    private var zenWasOnBeforeRules = false
    private var isStarted = false
    private var powerSource: CFRunLoopSource?

    init(model: AppModel) {
        self.model = model
    }

    /// Starts evaluating rules. Called once the menu bar has been scanned,
    /// so that what rules change can be undone.
    func start() {
        guard !isStarted else { return }
        isStarted = true
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
        observePowerSources()

        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                self?.evaluate()
            }
        }
        watchCaptureActivity()
        commandChecks.watch(model.settings.effectiveRules.commands)
        evaluate()
    }

    func rulesChanged() {
        guard isStarted else { return }
        let rules = Dictionary(model.settings.rules.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (id, entry) in applied {
            guard let rule = rules[id] else {
                // Rules that were deleted while active clean up without
                // reverting.
                finish(id, reverting: false, callsOffMoves: true)
                continue
            }
            if rule.action != entry.action {
                // An edited rule undoes its old action, and the next
                // evaluation applies the new one if it still matches.
                finish(id, reverting: rule.revertsWhenInactive, callsOffMoves: true)
                evaluator.forget(id)
            }
        }
        watchCaptureActivity()
        commandChecks.watch(model.settings.effectiveRules.commands)
        evaluate()
    }

    /// Microphones and cameras are only watched while an enabled rule
    /// depends on them.
    private func watchCaptureActivity() {
        let conditions = model.settings.effectiveRules.filter(\.isEnabled).flatMap(\.conditions)
        let microphones = conditions.contains(.microphoneInUse)
        let cameras = conditions.contains(.cameraInUse)
        guard microphones || cameras || watchesCaptureActivity else { return }
        watchesCaptureActivity = microphones || cameras
        captureActivity.watch(microphones: microphones, cameras: cameras)
    }

    func evaluate() {
        guard isStarted else { return }
        context = SystemSignals.snapshot(isOnline: isOnline, capture: capture, succeededCommands: succeededCommands)
        let transitions = evaluator.update(rules: model.settings.effectiveRules, context: context)
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
        let id = rule.id
        pendingMoves[id]?.cancel()
        pendingMoves[id] = nil
        // A revert that has not finished is no longer needed when the rule
        // does the same again; it keeps the rule's snapshot. A different
        // action waits for it.
        let unfinishedRevert = pendingReverts.removeValue(forKey: id)
        let repeatsAction = unfinishedRevert?.action == rule.action
        if repeatsAction {
            unfinishedRevert?.task.cancel()
        }
        let snapshot = repeatsAction ? unfinishedRevert?.snapshot ?? Snapshot() : Snapshot()
        let revertToFinish = repeatsAction ? nil : unfinishedRevert?.task
        let reveal = model.reveal
        var entry = Applied(action: rule.action)
        switch rule.action {
        case .revealHidden, .revealAll:
            reveal.reveal(all: rule.action == .revealAll, trigger: .rule)
            reveal.hold()
            revealRules.insert(id)
            entry.cleanup = { [weak self] in
                self?.revealRules.remove(id)
                reveal.release()
            }
            entry.revert = { [weak self] in
                guard self?.revealRules.isEmpty ?? true else { return }
                reveal.collapse(trigger: .rule)
            }
        case .collapse:
            reveal.collapse(trigger: .rule)
        case .zen:
            if zenRules.isEmpty {
                zenWasOnBeforeRules = model.isZenActive
            }
            zenRules.insert(id)
            model.setZen(true, announce: false)
            entry.cleanup = { [weak self] in
                self?.zenRules.remove(id)
            }
            entry.revert = { [weak self] in
                guard let self, self.zenRules.isEmpty, !self.zenWasOnBeforeRules else { return }
                self.model.setZen(false, announce: false)
            }
        case .applyScene(let sceneID):
            guard let scene = model.settings.scenes.first(where: { $0.id == sceneID }) else { break }
            pendingMoves[id] = Task { [weak self] in
                await revertToFinish?.value
                guard let self, !Task.isCancelled else { return }
                if snapshot.layout == nil {
                    await self.model.inventory.refresh()
                    snapshot.layout = self.model.inventory.currentLayout()
                }
                await self.model.applyScene(scene, automatic: true)
            }
            entry.revert = { [weak self] in
                self?.scheduleRevert(id, action: rule.action, snapshot: snapshot) { model in
                    guard let layout = snapshot.layout else { return }
                    try await model.mover.apply(layout, automatic: true)
                }
            }
        case .showItem(let key), .hideItem(let key), .stashItem(let key):
            guard let target = rule.action.targetSection else { break }
            pendingMoves[id] = Task { [weak self] in
                await revertToFinish?.value
                // The item may not be in the menu bar yet, for example
                // right after its app launched.
                guard let self, !Task.isCancelled, let item = await self.waitForItem(key) else { return }
                if snapshot.section == nil {
                    snapshot.section = item.section
                }
                do {
                    try await self.model.mover.move(key, to: target, automatic: true)
                } catch is CancellationError {
                } catch {
                    Log.rules.error("Rule move failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            entry.revert = { [weak self] in
                self?.scheduleRevert(id, action: rule.action, snapshot: snapshot) { model in
                    guard let section = snapshot.section else { return }
                    try await model.mover.move(key, to: section, automatic: true)
                }
            }
        }
        applied[id] = entry
    }

    private func deactivate(_ rule: AutomationRule) {
        Log.rules.info("Rule deactivated: \(rule.name, privacy: .public)")
        // A rule that is undone calls off moves it has not made yet. One
        // that is not undone still makes them, unless rules were paused.
        let callsOffMoves = rule.revertsWhenInactive || model.settings.rulesPaused
        finish(rule.id, reverting: rule.revertsWhenInactive, callsOffMoves: callsOffMoves)
    }

    /// Cleans up after a rule and, if asked, undoes what it did.
    private func finish(_ id: UUID, reverting: Bool, callsOffMoves: Bool) {
        if callsOffMoves {
            pendingMoves[id]?.cancel()
            pendingMoves[id] = nil
        }
        guard let entry = applied.removeValue(forKey: id) else { return }
        entry.cleanup()
        if reverting {
            entry.revert()
        }
    }

    /// Moves things back in the background, once the mouse and keyboard
    /// are idle.
    private func scheduleRevert(
        _ id: UUID,
        action: RuleAction,
        snapshot: Snapshot,
        _ work: @escaping @MainActor (AppModel) async throws -> Void
    ) {
        let token = UUID()
        let task = Task { [weak self] in
            guard let model = self?.model else { return }
            do {
                try await work(model)
            } catch is CancellationError {
                return
            } catch {
                Log.rules.error("Rule revert failed: \(error.localizedDescription, privacy: .public)")
            }
            if self?.pendingReverts[id]?.token == token {
                self?.pendingReverts[id] = nil
            }
        }
        pendingReverts[id] = PendingRevert(action: action, snapshot: snapshot, task: task, token: token)
    }

    /// The item, waiting up to half a minute for it to appear.
    private func waitForItem(_ key: MenuItemKey) async -> MenuBarItem? {
        let deadline = Date().addingTimeInterval(30)
        while !Task.isCancelled {
            if let item = model.inventory.item(for: key) { return item }
            guard Date() < deadline else { return nil }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await model.inventory.refresh()
        }
        return nil
    }

    /// Evaluates the rules as soon as the Mac switches between battery and
    /// power, instead of at the next periodic check.
    private func observePowerSources() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let controller = Unmanaged<AutomationController>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                controller.evaluate()
            }
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        powerSource = source
    }
}
