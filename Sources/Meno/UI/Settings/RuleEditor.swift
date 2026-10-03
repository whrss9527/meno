import MenoCore
import SwiftUI

/// Creates or edits a rule.
struct RuleEditor: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var conditions: [EditableCondition]
    @State private var action: RuleAction
    @State private var reverts: Bool
    @State private var requiresAll: Bool
    @State private var minimumDuration: TimeInterval
    /// Whether the minimum duration follows the conditions, as suggested for
    /// them, until it is picked by hand.
    @State private var waitFollowsConditions: Bool

    /// The minimum durations to pick from, in seconds.
    private static let waits: [TimeInterval] = [0, 3, 10, 30, 60, 300]

    private let ruleID: UUID
    private let isEnabled: Bool
    let isNew: Bool
    let scenes: [LayoutScene]
    let items: [MenuBarItem]
    /// Tells which conditions hold now.
    @ObservedObject var automation: AutomationController
    let onSave: (AutomationRule) -> Void

    struct EditableCondition: Identifiable {
        let id = UUID()
        var condition: RuleCondition
    }

    init(
        draft: AutomationRule,
        isNew: Bool,
        scenes: [LayoutScene],
        items: [MenuBarItem],
        automation: AutomationController,
        onSave: @escaping (AutomationRule) -> Void
    ) {
        _name = State(initialValue: draft.name)
        _conditions = State(initialValue: draft.conditions.map { EditableCondition(condition: $0) })
        _action = State(initialValue: draft.action)
        _reverts = State(initialValue: draft.revertsWhenInactive)
        _requiresAll = State(initialValue: draft.requiresAll)
        _minimumDuration = State(initialValue: draft.minimumDuration)
        _waitFollowsConditions = State(initialValue: draft.minimumDuration == AutomationRule.suggestedMinimumDuration(for: draft.conditions))
        ruleID = draft.id
        isEnabled = draft.isEnabled
        self.isNew = isNew
        self.scenes = scenes
        self.items = items
        self.automation = automation
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(isNew ? "New Rule" : "Edit Rule")
                .font(.system(size: 20, weight: .bold, design: .rounded))

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 10) {
                Picker(selection: $requiresAll) {
                    Text("When all of these are true").tag(true)
                    Text("When any of these is true").tag(false)
                } label: {
                    Text("Conditions")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                ForEach($conditions) { $entry in
                    HStack(spacing: 8) {
                        ConditionEditor(condition: $entry.condition)
                        Spacer(minLength: 0)
                        // Network conditions and commands show their own.
                        if entry.condition.kind != .network, entry.condition.kind != .commandSucceeds,
                           let holds = automation.holdsNow(entry.condition, in: conditions.map(\.condition), requiresAll: requiresAll) {
                            ConditionStatus(holds: holds)
                        }
                        Button {
                            conditions.removeAll { $0.id == entry.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(conditions.count <= 1)
                        .accessibilityLabel(Text("Remove Condition"))
                    }
                }
                if conditions.contains(where: { $0.condition.kind == .commandSucceeds }) {
                    Text("Commands run with zsh every 10 seconds while the rule is on. A command counts as true when it exits with status 0; one that takes longer than 5 seconds is stopped.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    Menu {
                        ForEach(RuleCondition.Kind.allCases, id: \.self) { kind in
                            Button(kind.title) {
                                conditions.append(EditableCondition(condition: kind.startingCondition))
                            }
                        }
                    } label: {
                        Label("Add Condition", systemImage: "plus")
                    }
                    .fixedSize()
                    Spacer(minLength: 8)
                    if let met = conditionsMet {
                        Label(
                            met ? String(localized: "The conditions are met now.") : String(localized: "The conditions are not met now."),
                            systemImage: met ? "checkmark.circle.fill" : "circle.dashed"
                        )
                        .font(.system(size: 11))
                        .foregroundStyle(met ? Color.green : Color.secondary)
                    }
                }
                Picker(selection: Binding(get: { minimumDuration }, set: {
                    minimumDuration = $0
                    waitFollowsConditions = false
                })) {
                    ForEach(waitChoices, id: \.self) { seconds in
                        Text(verbatim: seconds == 0 ? String(localized: "Off") : Formatters.duration(seconds)).tag(seconds)
                    }
                } label: {
                    Text("Ignore changes shorter than")
                }
                .pickerStyle(.menu)
                .fixedSize()
                if minimumDuration > 0 {
                    Text("The rule acts once its conditions have held this long, and ends once they have stopped as long, so that a quick switch between apps or a short pause does not move items back and forth.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .onChange(of: conditions.map(\.condition)) { _, conditions in
                if waitFollowsConditions {
                    minimumDuration = AutomationRule.suggestedMinimumDuration(for: conditions)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .menoGlassCard(cornerRadius: 14)

            VStack(alignment: .leading, spacing: 10) {
                Text("Then")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                ActionEditor(action: $action, scenes: scenes, items: items)
                Toggle("Undo when the conditions stop being true", isOn: $reverts)
                    .toggleStyle(.checkbox)
                if action.itemKey != nil {
                    Text("Moving items can briefly take over the pointer.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .menoGlassCard(cornerRadius: 14)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add Rule" : "Save") {
                    onSave(rule)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(24)
        .frame(width: 600)
        .background {
            ZStack {
                VisualEffectBackground(material: .sheet, blending: .behindWindow)
                AuroraBackground(intensity: 0.6)
            }
        }
    }

    private var rule: AutomationRule {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var rule = AutomationRule(
            id: ruleID,
            name: trimmed,
            isEnabled: isEnabled,
            conditions: conditions.map(\.condition),
            action: action,
            revertsWhenInactive: reverts,
            requiresAll: requiresAll,
            minimumDuration: minimumDuration
        )
        if trimmed.isEmpty {
            rule.name = RuleDescriber.describe(action, scenes: scenes, items: items).capitalizedFirstLetter
        }
        return rule
    }

    /// The minimum durations to pick from, with the rule's own if it is
    /// another one, such as from a file of someone else's.
    private var waitChoices: [TimeInterval] {
        Self.waits.contains(minimumDuration) ? Self.waits : (Self.waits + [minimumDuration]).sorted()
    }

    /// Whether the conditions hold now, when Meno knows.
    private var conditionsMet: Bool? {
        let all = conditions.map(\.condition)
        return AutomationRule.conditionsHold(
            all.map { automation.holdsNow($0, in: all, requiresAll: requiresAll) },
            requiresAll: requiresAll
        )
    }

    private var isValid: Bool {
        guard !conditions.isEmpty else { return false }
        for entry in conditions {
            switch entry.condition {
            case .appFrontmost(let id), .appRunning(let id):
                if id.isEmpty { return false }
            case .displayConnected(let name), .menuBarOnDisplay(let name):
                if name.isEmpty { return false }
            case .commandSucceeds:
                if entry.condition.command == nil { return false }
            case .network(let router, _):
                if router.isEmpty { return false }
            case .weekdays(let days):
                if days.isEmpty { return false }
            default:
                break
            }
        }
        switch action {
        case .applyScene(let id):
            return scenes.contains { $0.id == id }
        case .showItem(let key), .hideItem(let key), .stashItem(let key):
            return key != .placeholder
        default:
            return true
        }
    }
}

private struct ConditionEditor: View {
    @Binding var condition: RuleCondition
    @State private var isTesting = false
    @State private var testResult: Bool?
    /// The networks the Mac is on, once looked up.
    @State private var currentRouters: Set<String>?
    /// Set to look up the current network for the condition.
    @State private var lookup: UUID?
    @State private var isLookingUp = false
    /// The last lookup found no network.
    @State private var lookupFailed = false
    /// What the last lookup found, applied through the row's binding as it
    /// is then: rows move when others are removed meanwhile.
    @State private var found: FoundNetwork?

    private struct FoundNetwork: Equatable {
        let token = UUID()
        let identifier: String
    }

    var body: some View {
        HStack(spacing: 8) {
            Picker("", selection: Binding(get: { condition.kind }, set: { condition = $0.startingCondition })) {
                ForEach(RuleCondition.Kind.allCases, id: \.self) { kind in
                    Label(kind.title, systemImage: kind.symbol).tag(kind)
                }
            }
            .labelsHidden()
            .frame(width: 250)
            parameters
        }
        .task(id: condition.kind) {
            testResult = nil
            lookupFailed = false
            // Whether the network of the condition is the current one.
            guard condition.kind == .network else { return }
            let networks = await NetworkRouters.current()
            guard !Task.isCancelled else { return }
            currentRouters = Set(networks.map(\.identifier))
        }
        .task(id: lookup) {
            guard lookup != nil else { return }
            isLookingUp = true
            let networks = await NetworkRouters.current()
            // A row that was removed meanwhile is gone.
            guard !Task.isCancelled else { return }
            isLookingUp = false
            currentRouters = Set(networks.map(\.identifier))
            lookupFailed = networks.isEmpty
            found = networks.first.map { FoundNetwork(identifier: $0.identifier) }
        }
        .onChange(of: found) {
            guard let found, case .network(_, let name) = condition else { return }
            condition = .network(router: found.identifier, name: name)
        }
    }

    @ViewBuilder
    private var parameters: some View {
        switch condition {
        case .appFrontmost(let id):
            AppPicker(bundleID: Binding(get: { id }, set: { condition = .appFrontmost(bundleID: $0) }))
        case .appRunning(let id):
            AppPicker(bundleID: Binding(get: { id }, set: { condition = .appRunning(bundleID: $0) }))
        case .displayConnected(let name):
            DisplayPicker(name: Binding(get: { name }, set: { condition = .displayConnected(name: $0) }))
        case .menuBarOnDisplay(let name):
            DisplayPicker(name: Binding(get: { name }, set: { condition = .menuBarOnDisplay(name: $0) }))
        case .batteryBelow(let percent):
            Stepper(value: Binding(get: { percent }, set: { condition = .batteryBelow(percent: $0) }), in: 5...95, step: 5) {
                Text(verbatim: "\(percent)%")
                    .monospacedDigit()
            }
        case .timeWindow(let start, let end):
            HStack(spacing: 6) {
                MinutePicker(minute: Binding(get: { start }, set: { condition = .timeWindow(startMinute: $0, endMinute: end) }))
                Text("to")
                    .foregroundStyle(.secondary)
                MinutePicker(minute: Binding(get: { end }, set: { condition = .timeWindow(startMinute: start, endMinute: $0) }))
            }
        case .weekdays(let days):
            WeekdayPicker(days: Binding(get: { days }, set: { condition = .weekdays(days: $0) }))
        case .commandSucceeds(let command):
            TextField(
                String(localized: "Shell command"),
                text: Binding(get: { command }, set: { condition = .commandSucceeds(command: $0) })
            )
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12, design: .monospaced))
            .autocorrectionDisabled()
            .frame(minWidth: 160)
            .onChange(of: command) { testResult = nil }
            Button {
                test(command)
            } label: {
                if isTesting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Test")
                }
            }
            .disabled(condition.command == nil || isTesting)
            if let testResult {
                let label = testResult
                    ? String(localized: "The command succeeded.")
                    : String(localized: "The command failed or took too long.")
                Image(systemName: testResult ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(testResult ? Color.green : Color.red)
                    .help(label)
                    .accessibilityLabel(label)
            }
        case .network(let router, let name):
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    TextField(
                        String(localized: "Network name"),
                        text: Binding(get: { name }, set: { condition = .network(router: router, name: $0) })
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                    if !router.isEmpty, let currentRouters {
                        let connected = currentRouters.contains(router)
                        let label = connected ? String(localized: "Connected now") : String(localized: "Not connected now")
                        Image(systemName: connected ? "checkmark.circle.fill" : "circle.dashed")
                            .foregroundStyle(connected ? Color.green : Color.secondary)
                            .help(label)
                            .accessibilityLabel(label)
                    }
                }
                Button {
                    lookup = UUID()
                } label: {
                    if isLookingUp {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Use Current Network")
                    }
                }
                .disabled(isLookingUp)
                .help(Text("Meno recognizes a network by its router, without needing Location Services."))
                if lookupFailed {
                    Text("Meno could not tell which network this is.")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else if router.isEmpty {
                    Text("Click Use Current Network while the Mac is on it.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        default:
            EmptyView()
        }
    }
}

extension ConditionEditor {
    /// Runs the command once, off the main thread, and shows the result.
    private func test(_ command: String) {
        isTesting = true
        testResult = nil
        Task {
            let succeeded = await Task.detached { CommandChecks.succeeds(command) }.value
            isTesting = false
            testResult = succeeded
        }
    }
}

private struct ActionEditor: View {
    @Binding var action: RuleAction
    let scenes: [LayoutScene]
    let items: [MenuBarItem]

    var body: some View {
        HStack(spacing: 8) {
            Picker("", selection: Binding(get: { action.kind }, set: { action = defaultAction(for: $0) })) {
                ForEach(RuleAction.Kind.allCases, id: \.self) { kind in
                    Label(kind.title, systemImage: kind.symbol).tag(kind)
                }
            }
            .labelsHidden()
            .frame(width: 240)
            parameters
        }
    }

    @ViewBuilder
    private var parameters: some View {
        switch action {
        case .applyScene(let id):
            if scenes.isEmpty {
                Text("Save a scene first")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Picker("", selection: Binding(get: { id }, set: { action = .applyScene(id: $0) })) {
                    if !scenes.contains(where: { $0.id == id }) {
                        Text("Choose Scene").tag(id)
                    }
                    ForEach(scenes) { scene in
                        Text(verbatim: scene.name).tag(scene.id)
                    }
                }
                .labelsHidden()
                .frame(width: 200)
            }
        case .showItem(let key):
            ItemPicker(selection: Binding(get: { key }, set: { action = .showItem(key: $0) }), items: items)
        case .hideItem(let key):
            ItemPicker(selection: Binding(get: { key }, set: { action = .hideItem(key: $0) }), items: items)
        case .stashItem(let key):
            ItemPicker(selection: Binding(get: { key }, set: { action = .stashItem(key: $0) }), items: items)
        default:
            EmptyView()
        }
    }

    private func defaultAction(for kind: RuleAction.Kind) -> RuleAction {
        let key = action.itemKey ?? .placeholder
        switch kind {
        case .revealHidden: return .revealHidden
        case .revealAll: return .revealAll
        case .collapse: return .collapse
        case .zen: return .zen
        case .applyScene: return .applyScene(id: scenes.first?.id ?? UUID())
        case .showItem: return .showItem(key: key)
        case .hideItem: return .hideItem(key: key)
        case .stashItem: return .stashItem(key: key)
        }
    }
}

/// Marks whether a condition holds now.
private struct ConditionStatus: View {
    let holds: Bool

    var body: some View {
        let label = holds ? String(localized: "True now") : String(localized: "Not true now")
        Image(systemName: holds ? "checkmark.circle.fill" : "circle.dashed")
            .foregroundStyle(holds ? Color.green : Color.secondary)
            .help(label)
            .accessibilityLabel(label)
    }
}

/// Picks days of the week, shown in the order of the person's week.
struct WeekdayPicker: View {
    @Binding var days: [Int]

    var body: some View {
        let calendar = Calendar.current
        HStack(spacing: 2) {
            ForEach(Weekdays.ordered(startingOn: calendar.firstWeekday), id: \.self) { day in
                let selected = days.contains(day)
                let name = calendar.standaloneWeekdaySymbols[day - 1]
                Button {
                    days = Weekdays.toggling(day, in: days)
                } label: {
                    Text(verbatim: calendar.shortStandaloneWeekdaySymbols[day - 1])
                        .font(.system(size: 11, weight: selected ? .semibold : .regular))
                        .lineLimit(1)
                        .frame(minWidth: 22)
                        .padding(.horizontal, 2)
                        .padding(.vertical, 4)
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .background {
                            Capsule().fill(selected ? Color.accentColor : Color.primary.opacity(0.07))
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(Text(verbatim: name))
                .accessibilityLabel(Text(verbatim: name))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .fixedSize()
    }
}

/// Picks a time of day, stored as minutes after midnight.
struct MinutePicker: View {
    @Binding var minute: Int

    var body: some View {
        DatePicker("", selection: Binding(
            get: {
                Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            }
        ), displayedComponents: .hourAndMinute)
        .labelsHidden()
        .frame(width: 96)
    }
}

extension String {
    var capitalizedFirstLetter: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
