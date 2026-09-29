import Foundation

/// A snapshot of the system state that rules are evaluated against.
public struct RuleContext: Equatable, Sendable {
    public var frontmostBundleID: String?
    public var runningBundleIDs: Set<String>
    public var isOnBattery: Bool
    /// Battery charge in percent, or `nil` without a battery.
    public var batteryLevel: Int?
    public var isLowPowerMode: Bool
    public var externalDisplayCount: Int
    /// Names of the connected displays.
    public var displayNames: Set<String>
    /// Minutes since local midnight.
    public var minuteOfDay: Int
    public var isOnline: Bool
    /// Whether any app records from a microphone.
    public var microphoneInUse: Bool
    /// Whether any app uses a camera.
    public var cameraInUse: Bool

    public init(
        frontmostBundleID: String? = nil,
        runningBundleIDs: Set<String> = [],
        isOnBattery: Bool = false,
        batteryLevel: Int? = nil,
        isLowPowerMode: Bool = false,
        externalDisplayCount: Int = 0,
        displayNames: Set<String> = [],
        minuteOfDay: Int = 0,
        isOnline: Bool = true,
        microphoneInUse: Bool = false,
        cameraInUse: Bool = false
    ) {
        self.frontmostBundleID = frontmostBundleID
        self.runningBundleIDs = runningBundleIDs
        self.isOnBattery = isOnBattery
        self.batteryLevel = batteryLevel
        self.isLowPowerMode = isLowPowerMode
        self.externalDisplayCount = externalDisplayCount
        self.displayNames = displayNames
        self.minuteOfDay = minuteOfDay
        self.isOnline = isOnline
        self.microphoneInUse = microphoneInUse
        self.cameraInUse = cameraInUse
    }
}

/// Something that is either true or false about the system.
public enum RuleCondition: Codable, Hashable, Sendable {
    case appFrontmost(bundleID: String)
    case appRunning(bundleID: String)
    case onBattery
    case onPower
    case batteryBelow(percent: Int)
    case lowPowerMode
    case externalDisplay
    case noExternalDisplay
    /// A display with this name is connected, for example a monitor at the office.
    case displayConnected(name: String)
    /// Between two times of day, given in minutes after midnight. The window
    /// wraps around midnight when `startMinute > endMinute`.
    case timeWindow(startMinute: Int, endMinute: Int)
    case offline
    case microphoneInUse
    case cameraInUse

    public func isSatisfied(by context: RuleContext) -> Bool {
        switch self {
        case .appFrontmost(let bundleID):
            return context.frontmostBundleID == bundleID
        case .appRunning(let bundleID):
            return context.runningBundleIDs.contains(bundleID)
        case .onBattery:
            return context.isOnBattery
        case .onPower:
            return !context.isOnBattery
        case .batteryBelow(let percent):
            guard let level = context.batteryLevel else { return false }
            return level < percent
        case .lowPowerMode:
            return context.isLowPowerMode
        case .externalDisplay:
            return context.externalDisplayCount > 0
        case .noExternalDisplay:
            return context.externalDisplayCount == 0
        case .displayConnected(let name):
            return !name.isEmpty && context.displayNames.contains(name)
        case .timeWindow(let start, let end):
            let minute = context.minuteOfDay
            if start == end { return true }
            if start < end { return minute >= start && minute < end }
            return minute >= start || minute < end
        case .offline:
            return !context.isOnline
        case .microphoneInUse:
            return context.microphoneInUse
        case .cameraInUse:
            return context.cameraInUse
        }
    }

    /// A stable identifier of the condition's kind, used by editors.
    public var kind: Kind {
        switch self {
        case .appFrontmost: return .appFrontmost
        case .appRunning: return .appRunning
        case .onBattery: return .onBattery
        case .onPower: return .onPower
        case .batteryBelow: return .batteryBelow
        case .lowPowerMode: return .lowPowerMode
        case .externalDisplay: return .externalDisplay
        case .noExternalDisplay: return .noExternalDisplay
        case .displayConnected: return .displayConnected
        case .timeWindow: return .timeWindow
        case .offline: return .offline
        case .microphoneInUse: return .microphoneInUse
        case .cameraInUse: return .cameraInUse
        }
    }

    public enum Kind: String, CaseIterable, Sendable {
        case appFrontmost
        case appRunning
        case onBattery
        case onPower
        case batteryBelow
        case lowPowerMode
        case externalDisplay
        case noExternalDisplay
        case displayConnected
        case timeWindow
        case offline
        case microphoneInUse
        case cameraInUse

        /// A reasonable starting value for a new condition of this kind.
        public var defaultCondition: RuleCondition {
            switch self {
            case .appFrontmost: return .appFrontmost(bundleID: "")
            case .appRunning: return .appRunning(bundleID: "")
            case .onBattery: return .onBattery
            case .onPower: return .onPower
            case .batteryBelow: return .batteryBelow(percent: 20)
            case .lowPowerMode: return .lowPowerMode
            case .externalDisplay: return .externalDisplay
            case .noExternalDisplay: return .noExternalDisplay
            case .displayConnected: return .displayConnected(name: "")
            case .timeWindow: return .timeWindow(startMinute: 9 * 60, endMinute: 18 * 60)
            case .offline: return .offline
            case .microphoneInUse: return .microphoneInUse
            case .cameraInUse: return .cameraInUse
            }
        }
    }
}

/// What a rule does when its conditions become true.
public enum RuleAction: Codable, Hashable, Sendable {
    case revealHidden
    case revealAll
    case collapse
    case zen
    case applyScene(id: UUID)
    case showItem(key: MenuItemKey)
    case hideItem(key: MenuItemKey)
    case stashItem(key: MenuItemKey)

    public var kind: Kind {
        switch self {
        case .revealHidden: return .revealHidden
        case .revealAll: return .revealAll
        case .collapse: return .collapse
        case .zen: return .zen
        case .applyScene: return .applyScene
        case .showItem: return .showItem
        case .hideItem: return .hideItem
        case .stashItem: return .stashItem
        }
    }

    /// The item this action moves, if any.
    public var itemKey: MenuItemKey? {
        switch self {
        case .showItem(let key), .hideItem(let key), .stashItem(let key): return key
        default: return nil
        }
    }

    /// The section an item action moves its item into.
    public var targetSection: ItemSection? {
        switch self {
        case .showItem: return .visible
        case .hideItem: return .hidden
        case .stashItem: return .stash
        default: return nil
        }
    }

    public enum Kind: String, CaseIterable, Sendable {
        case revealHidden
        case revealAll
        case collapse
        case zen
        case applyScene
        case showItem
        case hideItem
        case stashItem

        public var needsItem: Bool {
            self == .showItem || self == .hideItem || self == .stashItem
        }
    }
}

/// "When all conditions are true, perform the action."
public struct AutomationRule: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    public var conditions: [RuleCondition]
    public var action: RuleAction
    /// Undo the action once the conditions stop being true.
    public var revertsWhenInactive: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        conditions: [RuleCondition],
        action: RuleAction,
        revertsWhenInactive: Bool = true
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.conditions = conditions
        self.action = action
        self.revertsWhenInactive = revertsWhenInactive
    }

    public func matches(_ context: RuleContext) -> Bool {
        isEnabled && !conditions.isEmpty && conditions.allSatisfy { $0.isSatisfied(by: context) }
    }
}

/// A change in whether a rule applies.
public enum RuleTransition: Hashable, Sendable {
    case activated(AutomationRule)
    case deactivated(AutomationRule)
}

/// Tracks which rules are active and reports edges.
public struct RuleEvaluator: Sendable {
    public private(set) var activeRuleIDs: Set<UUID> = []

    public init() {}

    /// Evaluates all rules and returns what changed since the last call.
    /// Deactivations come first, so reverts run before new actions.
    public mutating func update(rules: [AutomationRule], context: RuleContext) -> [RuleTransition] {
        let nowActive = Set(rules.filter { $0.matches(context) }.map(\.id))
        var transitions: [RuleTransition] = []
        for rule in rules.reversed() where activeRuleIDs.contains(rule.id) && !nowActive.contains(rule.id) {
            transitions.append(.deactivated(rule))
        }
        for rule in rules where nowActive.contains(rule.id) && !activeRuleIDs.contains(rule.id) {
            transitions.append(.activated(rule))
        }
        activeRuleIDs = nowActive
        return transitions
    }

    public mutating func reset() {
        activeRuleIDs = []
    }
}
