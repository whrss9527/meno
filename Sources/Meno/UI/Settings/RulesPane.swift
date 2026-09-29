import MenoCore
import SwiftUI

struct RulesPane: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var automation: AutomationController
    @ObservedObject var inventory: ItemInventory

    @State private var editing: EditorState?

    struct EditorState: Identifiable {
        let id = UUID()
        var rule: AutomationRule
        var isNew: Bool
    }

    var body: some View {
        VStack(spacing: 16) {
            SettingsCard("Rules", symbol: "wand.and.stars", footnote: "Rules are checked when apps switch, displays change, power or network changes, a microphone or camera starts or stops, and every 30 seconds.") {
                HStack(spacing: 10) {
                    Button {
                        editing = EditorState(rule: AutomationRule(name: "", conditions: [.onBattery], action: .revealHidden), isNew: true)
                    } label: {
                        Label("New Rule", systemImage: "plus")
                    }
                    .menoGlassButtonStyle(prominent: true)
                    Menu {
                        ForEach(RulePreset.allCases, id: \.self) { preset in
                            Button(preset.title) {
                                editing = EditorState(rule: preset.makeRule(model: model), isNew: true)
                            }
                        }
                    } label: {
                        Label("Start from a Preset", systemImage: "sparkles")
                    }
                    .fixedSize()
                    Spacer()
                    if !model.settings.rules.isEmpty {
                        Toggle("Pause All Rules", isOn: $model.settings.rulesPaused)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                }
            }

            if model.settings.rulesPaused, !model.settings.rules.isEmpty {
                Banner(
                    symbol: "pause.circle.fill",
                    tint: .orange,
                    title: "Rules are paused",
                    message: "While rules are paused, none of them applies. Rules that undo their action when it ends have undone it.",
                    actionTitle: "Resume Rules",
                    action: { model.settings.rulesPaused = false }
                )
            }

            if model.settings.rules.isEmpty {
                Text("No rules yet. Presets are a good way to begin.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }

            ForEach($model.settings.rules) { $rule in
                RuleCard(
                    rule: $rule,
                    isActive: automation.activeRuleIDs.contains(rule.id),
                    onEdit: { editing = EditorState(rule: rule, isNew: false) },
                    onDelete: { model.settings.rules.removeAll { $0.id == rule.id } }
                )
            }
        }
        .sheet(item: $editing) { state in
            RuleEditor(
                draft: state.rule,
                isNew: state.isNew,
                scenes: model.settings.scenes,
                items: inventory.items.filter { $0.kind != .marker }
            ) { saved in
                if let index = model.settings.rules.firstIndex(where: { $0.id == saved.id }) {
                    model.settings.rules[index] = saved
                } else {
                    model.settings.rules.append(saved)
                }
            }
        }
    }
}

private struct RuleCard: View {
    @Binding var rule: AutomationRule
    let isActive: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: rule.action.kind.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isActive ? Color.green : Color.accentColor)
                .frame(width: 36, height: 36)
                .background {
                    Circle().fill((isActive ? Color.green : Color.accentColor).opacity(0.14))
                }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(verbatim: rule.name.isEmpty ? String(localized: "Untitled Rule") : rule.name)
                        .font(.system(size: 14, weight: .semibold))
                    if isActive {
                        Text("Active")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .foregroundStyle(.green)
                            .background { Capsule().fill(Color.green.opacity(0.15)) }
                    }
                }
                Text(verbatim: RuleDescriber.describe(rule, scenes: model.settings.scenes, items: model.inventory.items))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle(isOn: $rule.isEnabled) {
                Text(verbatim: rule.name)
            }
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            Menu {
                Button("Edit…", action: onEdit)
                Button("Delete", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel(Text("More"))
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .menoGlassCard(cornerRadius: 18)
        .onTapGesture(count: 2, perform: onEdit)
    }
}

/// Builds sentences such as "When Keynote is in front, turn on Zen."
enum RuleDescriber {
    static func describe(_ rule: AutomationRule, scenes: [LayoutScene], items: [MenuBarItem]) -> String {
        let separator = rule.requiresAll ? String(localized: " and ") : String(localized: " or ")
        let conditions = rule.conditions.map(describe).joined(separator: separator)
        let action = describe(rule.action, scenes: scenes, items: items)
        var sentence = String(localized: "When \(conditions): \(action).")
        if rule.revertsWhenInactive {
            sentence += " " + String(localized: "Undone afterwards.")
        }
        return sentence
    }

    static func describe(_ condition: RuleCondition) -> String {
        switch condition {
        case .appFrontmost(let id):
            return String(localized: "\(AppDirectory.name(for: id)) is in front")
        case .appRunning(let id):
            return String(localized: "\(AppDirectory.name(for: id)) is running")
        case .onBattery:
            return String(localized: "on battery")
        case .onPower:
            return String(localized: "connected to power")
        case .batteryBelow(let percent):
            return String(localized: "battery below \(percent)%")
        case .lowPowerMode:
            return String(localized: "Low Power Mode is on")
        case .externalDisplay:
            return String(localized: "an external display is connected")
        case .noExternalDisplay:
            return String(localized: "no external display is connected")
        case .displayConnected(let name):
            return String(localized: "“\(name)” is connected")
        case .timeWindow(let start, let end):
            return String(localized: "between \(Formatters.time(minuteOfDay: start)) and \(Formatters.time(minuteOfDay: end))")
        case .offline:
            return String(localized: "offline")
        case .microphoneInUse:
            return String(localized: "a microphone is in use")
        case .cameraInUse:
            return String(localized: "a camera is in use")
        case .commandSucceeds(let command):
            return String(localized: "“\(command)” succeeds")
        }
    }

    static func describe(_ action: RuleAction, scenes: [LayoutScene], items: [MenuBarItem]) -> String {
        func name(_ key: MenuItemKey) -> String {
            items.first { $0.key == key }?.displayName ?? AppDirectory.name(for: key.owner)
        }
        switch action {
        case .revealHidden: return String(localized: "show hidden items")
        case .revealAll: return String(localized: "show everything")
        case .collapse: return String(localized: "hide items")
        case .zen: return String(localized: "turn on Zen")
        case .applyScene(let id):
            let scene = scenes.first { $0.id == id }?.name ?? String(localized: "a deleted scene")
            return String(localized: "apply “\(scene)”")
        case .showItem(let key): return String(localized: "keep \(name(key)) visible")
        case .hideItem(let key): return String(localized: "hide \(name(key))")
        case .stashItem(let key): return String(localized: "stash \(name(key))")
        }
    }
}

/// Ready-made rules.
enum RulePreset: CaseIterable {
    case presenting
    case videoCall
    case lowBattery
    case desk
    case offline
    case evening

    var title: String {
        switch self {
        case .presenting: return String(localized: "Zen while presenting with Keynote")
        case .videoCall: return String(localized: "Zen during calls")
        case .lowBattery: return String(localized: "Show the battery when it runs low")
        case .desk: return String(localized: "Apply a scene at the desk")
        case .offline: return String(localized: "Show hidden items while offline")
        case .evening: return String(localized: "Quiet menu bar in the evening")
        }
    }

    @MainActor
    func makeRule(model: AppModel) -> AutomationRule {
        switch self {
        case .presenting:
            return AutomationRule(name: title, conditions: [.appFrontmost(bundleID: "com.apple.Keynote")], action: .zen)
        case .videoCall:
            return AutomationRule(name: title, conditions: [.microphoneInUse], action: .zen)
        case .lowBattery:
            let battery = model.inventory.items.first {
                $0.kind == .system && (($0.identifier ?? "") + $0.displayName).lowercased().contains("battery")
            }
            return AutomationRule(
                name: title,
                conditions: [.onBattery, .batteryBelow(percent: 20)],
                action: battery.map { RuleAction.showItem(key: $0.key) } ?? RuleAction.revealHidden
            )
        case .desk:
            let action: RuleAction = model.settings.scenes.first.map { RuleAction.applyScene(id: $0.id) } ?? RuleAction.revealHidden
            return AutomationRule(name: title, conditions: [.externalDisplay], action: action)
        case .offline:
            return AutomationRule(name: title, conditions: [.offline], action: .revealHidden)
        case .evening:
            return AutomationRule(name: title, conditions: [.timeWindow(startMinute: 21 * 60, endMinute: 7 * 60)], action: .zen)
        }
    }
}
