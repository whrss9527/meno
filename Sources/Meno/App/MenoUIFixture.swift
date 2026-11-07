#if MENO_UI_FIXTURE
import AppKit
import MenoCore
import SwiftUI

/// Only compiled by build-ui-fixture.sh; never starts AppModel's lifecycle.
@MainActor
final class MenoUIFixture: NSObject, NSApplicationDelegate, ObservableObject {
    @Published var lastAction = "No action yet / 尚未操作"
    @Published var geometry = "No layout yet"
    private var workspaceMode = 0
    private var window: NSWindow?
    private var model: AppModel?
    private var palette: QuickOpenController?

    nonisolated static func run() {
        MainActor.assumeIsolated {
            precondition(Bundle.main.bundleIdentifier == "org.codex.fixture.meno")
            let app = NSApplication.shared
            let delegate = MenoUIFixture()
            app.delegate = delegate
            app.setActivationPolicy(.regular)
            withExtendedLifetime(delegate) { app.run() }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("meno-ui-fixture-\(UUID())")
        let images = ItemImageCache(capture: { _ in [:] })
        let model = AppModel(storage: Storage(directory: directory),
                             permissions: PermissionCenter(accessibility: false, screenRecording: false, accessibilityWasGranted: false),
                             images: images, loginState: (false, false))
        self.model = model
        let names = [
            "Work Cloud — synchronization paused while uploading a very long project archive",
            "工作同步中心——正在同步包含非常长名称的设计稿、文档与项目归档",
            "Audio Studio / 音频工作室", "Battery Monitor / 电池监控", "Calendar / 日历",
            "Clipboard / 剪贴板", "Downloads / 下载", "Focus / 专注", "Network / 网络",
            "Notes / 笔记", "Screen Tools / 屏幕工具", "Weather / 天气"
        ]
        let itemDetail = "Synthetic item / 合成条目"
        let items = names.enumerated().map { index, name in
            MenuBarItem(key: MenuItemKey(owner: "fixture.meno", token: "item-\(index)"), kind: .app,
                        pid: -1, bundleID: nil, appName: "Fixture App \(index + 1)", displayName: name,
                        detail: itemDetail, identifier: nil, frame: .zero,
                        section: index.isMultiple(of: 2) ? .hidden : .visible, isMovable: false,
                        element: nil, keywords: [name, "fixture", "ceshi"], markerID: nil)
        }
        images.setCustomSymbols(Dictionary(uniqueKeysWithValues: items.map { ($0.key.rawValue, "square.grid.2x2") }))
        let commands = ["Arrange Layout / 排列布局", "Apply Long Work Scene / 应用工作场景"].enumerated().map { index, name in
            QuickCommand(id: "fixture-\(index)", title: name, symbol: "gearshape", keywords: ["layout", "scene"]) {}
        }
        palette = QuickOpenController(model: model, contentSource: .init(items: items, commands: commands, activate: { [weak self] result in
            switch result {
            case .item(let item): self?.lastAction = "Opened / 已打开: \(item.displayName)"
            case .command(let command): self?.lastAction = "Ran / 已运行: \(command.title)"
            }
        }, workspace: { [weak self] in self?.workspace() ?? (.zero, .zero) }, didLayout: { [weak self] frame, available in
            let value = "Panel \(Int(frame.width))×\(Int(frame.height)) · available \(Int(available.width))×\(Int(available.height)) · contained: \(available.contains(frame))"
            if self?.geometry != value { self?.geometry = value }
        }))
        installMenu()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 240),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Meno UI Fixture — isolated production Quick Open"
        window.contentView = NSHostingView(rootView: FixtureControls(fixture: self))
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        palette?.show()
    }

    func openPalette() { palette?.show() }

    func setWorkspace(_ mode: Int) { workspaceMode = mode; palette?.hide(); palette?.show() }

    private func workspace() -> (screen: CGRect, visible: CGRect) {
        guard let actual = NSScreen.main else { return (.zero, .zero) }
        guard workspaceMode != 0 else { return (actual.frame, actual.visibleFrame) }
        let screen = CGRect(x: actual.frame.midX - 400, y: actual.frame.midY - 300, width: 800, height: 600)
        if workspaceMode == 1 {
            return (screen, CGRect(x: screen.minX, y: screen.minY + 80, width: 800, height: 496))
        }
        return (screen, CGRect(x: screen.minX + 140, y: screen.minY + 120, width: 520, height: 360))
    }

    @objc private func showControls(_ sender: Any?) { window?.makeKeyAndOrderFront(nil) }
    @objc private func showPalette(_ sender: Any?) { openPalette() }

    func language(_ code: String) {
        let process = Process()
        process.executableURL = Bundle.main.executableURL
        process.arguments = ["-AppleLanguages", "(\(code))"]
        do { try process.run(); NSApp.terminate(nil) }
        catch { lastAction = error.localizedDescription }
    }

    private func installMenu() {
        let menu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Fixture", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem(); appItem.submenu = appMenu; menu.addItem(appItem)
        let editTitle = "Edit"
        let edit = NSMenu(title: editTitle)
        for (title, action, key) in [("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"),
                                     ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        let editItem = NSMenuItem(); editItem.submenu = edit; menu.addItem(editItem)
        let windowTitle = "Window"
        let windows = NSMenu(title: windowTitle)
        let controls = windows.addItem(withTitle: "Show Controls", action: #selector(showControls(_:)), keyEquivalent: "0")
        controls.target = self; controls.keyEquivalentModifierMask = [.command, .option]
        let palette = windows.addItem(withTitle: "Open Quick Open", action: #selector(showPalette(_:)), keyEquivalent: "p")
        palette.target = self; palette.keyEquivalentModifierMask = [.command, .option]
        let windowItem = NSMenuItem(); windowItem.submenu = windows; menu.addItem(windowItem)
        NSApp.mainMenu = menu; NSApp.windowsMenu = windows
    }
}

private struct FixtureControls: View {
    @ObservedObject var fixture: MenoUIFixture
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: "Production QuickOpenView + QuickOpenController · synthetic items · no AX or screen capture")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(action: { fixture.openPalette() }) { Text(verbatim: "Open Quick Open / 打开搜索") }.keyboardShortcut("k")
                Button(action: { NSApp.appearance = NSAppearance(named: .aqua) }) { Text(verbatim: "Light") }
                Button(action: { NSApp.appearance = NSAppearance(named: .darkAqua) }) { Text(verbatim: "Dark") }
                Button(action: { fixture.language("en") }) { Text(verbatim: "English ↻") }
                Button(action: { fixture.language("zh-Hans") }) { Text(verbatim: "中文 ↻") }
            }
            HStack {
                Button(action: { fixture.setWorkspace(0) }) { Text(verbatim: "Actual desktop") }
                Button(action: { fixture.setWorkspace(1) }) { Text(verbatim: "Simulated Dock 800×496") }
                Button(action: { fixture.setWorkspace(2) }) { Text(verbatim: "Simulated compact 520×360") }
            }
            Text(verbatim: fixture.geometry).font(.caption).monospacedDigit()
            Text(fixture.lastAction).lineLimit(2).textSelection(.enabled)
        }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
#endif
