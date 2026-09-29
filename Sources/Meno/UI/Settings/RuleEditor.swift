import MenoCore
import SwiftUI

/// Creates or edits a rule.
struct RuleEditor: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var conditions: [EditableCondition]
    @State private var action: RuleAction
    @State private var reverts: Bool

    private let ruleID: UUID
    private let isEnabled: Bool
    let isNew: Bool
    let scenes: [LayoutScene]
    let items: [MenuBarItem]
    let onSave: (AutomationRule) -> Void

    struct EditableCondition: Identifiable {
        let id = UUID()
        var condition: RuleCondition
    }

    init(draft: AutomationRule, isNew: Bool, scenes: [LayoutScene], items: [MenuBarItem], onSave: @escaping (AutomationRule) -> Void) {
        _name = State(initialValue: draft.name)
        _conditions = State(initialValue: draft.conditions.map { EditableCondition(condition: $0) })
        _action = State(initialValue: draft.action)
        _reverts = State(initialValue: draft.revertsWhenInactive)
        ruleID = draft.id
        isEnabled = draft.isEnabled
        self.isNew = isNew
        self.scenes = scenes
        self.items = items
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(isNew ? "New Rule" : "Edit Rule")
                .font(.system(size: 20, weight: .bold, design: .rounded))

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 10) {
                Text("When all of these are true")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                ForEach($conditions) { $entry in
                    HStack(spacing: 8) {
                        ConditionEditor(condition: $entry.condition)
                        Spacer(minLength: 0)
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
                Menu {
                    ForEach(RuleCondition.Kind.allCases, id: \.self) { kind in
                        Button(kind.title) {
                            conditions.append(EditableCondition(condition: kind.defaultCondition))
                        }
                    }
                } label: {
                    Label("Add Condition", systemImage: "plus")
                }
                .fixedSize()
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
                    Text("Moving items briefly takes over the pointer.")
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
            revertsWhenInactive: reverts
        )
        if trimmed.isEmpty {
            rule.name = RuleDescriber.describe(action, scenes: scenes, items: items).capitalizedFirstLetter
        }
        return rule
    }

    private var isValid: Bool {
        guard !conditions.isEmpty else { return false }
        for entry in conditions {
            switch entry.condition {
            case .appFrontmost(let id), .appRunning(let id):
                if id.isEmpty { return false }
            case .commandSucceeds:
                if entry.condition.command == nil { return false }
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

    var body: some View {
        HStack(spacing: 8) {
            Picker("", selection: Binding(get: { condition.kind }, set: { condition = $0.defaultCondition })) {
                ForEach(RuleCondition.Kind.allCases, id: \.self) { kind in
                    Label(kind.title, systemImage: kind.symbol).tag(kind)
                }
            }
            .labelsHidden()
            .frame(width: 250)
            parameters
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
