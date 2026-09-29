import AppKit
import MenoCore
import SwiftUI

/// Records a global keyboard shortcut.
///
/// While recording, Meno's own shortcuts are unregistered so that pressing
/// an existing shortcut can be recorded again. Only one recorder records at
/// a time, and recording stops when Meno is no longer the active app.
struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo?
    /// What the shortcut is for, so VoiceOver can say it.
    var purpose: String?
    @EnvironmentObject private var model: AppModel

    @State private var id = UUID()
    @State private var isRecording = false
    @State private var monitor: LocalEventMonitor?
    @State private var problem: KeyCombo.Problem?

    var body: some View {
        HStack(spacing: 6) {
            Button {
                isRecording ? stop() : start()
            } label: {
                Text(verbatim: label)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .frame(minWidth: 120)
                    .foregroundStyle(labelColor)
            }
            .menoGlassButtonStyle(prominent: isRecording)
            .help(helpText)
            .accessibilityLabel(purpose.map { Text("Shortcut for \($0)") } ?? Text("Shortcut"))
            .accessibilityValue(Text(verbatim: label))
            if combo != nil, !isRecording {
                Button {
                    combo = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(Text("Remove shortcut"))
                .accessibilityLabel(Text("Remove shortcut"))
            }
        }
        .onDisappear(perform: stop)
        .onChange(of: model.activeShortcutRecorder) {
            if isRecording, model.activeShortcutRecorder != id {
                stop()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            stop()
        }
    }

    private var label: String {
        if isRecording {
            switch problem {
            case .needsModifier: return String(localized: "Add ⌘, ⌥ or ⌃")
            case .needsCommandOrControl: return String(localized: "Add ⌘ or ⌃")
            case nil: return String(localized: "Type a shortcut…")
            }
        }
        if let combo { return KeyboardLayout.displayString(for: combo) }
        return String(localized: "Record Shortcut")
    }

    private var labelColor: Color {
        if problem != nil { return .red }
        if isRefused || isUsedTwice { return .orange }
        return .primary
    }

    private var helpText: Text {
        if isRefused { return Text("macOS did not accept this shortcut. Another app may already use it.") }
        if isUsedTwice { return Text("This shortcut is used more than once in Meno. Only one of its uses works.") }
        return Text(verbatim: "")
    }

    /// Whether another of Meno's shortcuts is the same.
    private var isUsedTwice: Bool {
        guard let combo, !isRecording else { return false }
        return model.settings.hotkeyConflicts.contains(combo)
    }

    /// Whether macOS refused the recorded shortcut.
    private var isRefused: Bool {
        guard let combo, !isRecording else { return false }
        return model.refusedHotkeys.contains(combo)
    }

    private func start() {
        model.activeShortcutRecorder = id
        isRecording = true
        problem = nil
        TextEditingShortcuts.isSuspended = true
        model.hotkeys.unregisterAll()
        let monitor = LocalEventMonitor(mask: [.keyDown]) { event in
            handle(event)
            return true
        }
        monitor.start()
        self.monitor = monitor
    }

    private func stop() {
        monitor?.stop()
        monitor = nil
        guard isRecording else { return }
        isRecording = false
        problem = nil
        // Another recorder that started meanwhile keeps the shortcuts off.
        guard model.activeShortcutRecorder == id else { return }
        model.activeShortcutRecorder = nil
        TextEditingShortcuts.isSuspended = false
        model.registerHotkeys()
    }

    private func handle(_ event: NSEvent) {
        let modifiers = KeyboardLayout.modifiers(from: event.modifierFlags)
        if modifiers.isEmpty {
            switch event.keyCode {
            case 0x35: // escape
                stop()
                return
            case 0x33, 0x75: // delete, forward delete
                combo = nil
                stop()
                return
            default:
                break
            }
        }
        let candidate = KeyCombo(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        if let problem = candidate.problem(osMajorVersion: AppInfo.osMajorVersion) {
            self.problem = problem
            NSSound.beep()
            return
        }
        combo = candidate
        stop()
    }
}
