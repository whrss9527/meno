import AppKit
import MenoCore
import SwiftUI

/// Records a global keyboard shortcut.
///
/// While recording, Meno's own shortcuts are unregistered so that pressing
/// an existing shortcut can be recorded again.
struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo?
    @EnvironmentObject private var model: AppModel

    @State private var isRecording = false
    @State private var monitor: LocalEventMonitor?
    @State private var rejected = false

    var body: some View {
        HStack(spacing: 6) {
            Button {
                isRecording ? stop() : start()
            } label: {
                Text(verbatim: label)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .frame(minWidth: 120)
                    .foregroundStyle(rejected ? Color.red : Color.primary)
            }
            .menoGlassButtonStyle(prominent: isRecording)
            if combo != nil, !isRecording {
                Button {
                    combo = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(Text("Remove shortcut"))
            }
        }
        .onDisappear(perform: stop)
    }

    private var label: String {
        if isRecording { return String(localized: "Type a shortcut…") }
        if let combo { return KeyboardLayout.displayString(for: combo) }
        return String(localized: "Record Shortcut")
    }

    private func start() {
        isRecording = true
        rejected = false
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
        guard candidate.isValidGlobalShortcut else {
            rejected = true
            NSSound.beep()
            return
        }
        rejected = false
        combo = candidate
        stop()
    }
}
