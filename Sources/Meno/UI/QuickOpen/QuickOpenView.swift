import MenoCore
import SwiftUI

struct QuickOpenView: View {
    @ObservedObject var controller: QuickOpenController
    @ObservedObject var model: AppModel
    @ObservedObject var images: ItemImageCache
    @ObservedObject var changes: ChangeWatcher

    @FocusState private var fieldFocused: Bool

    private var listHeight: CGFloat {
        let rows = min(controller.results.count, QuickOpenController.maximumVisibleRows)
        return CGFloat(rows) * QuickOpenController.rowHeight + 12
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .layoutPriority(1)
            if !controller.results.isEmpty {
                Divider().opacity(0.5)
                resultList
            } else if !controller.query.isEmpty {
                Divider().opacity(0.5)
                Text("No matching items")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            }
            Divider().opacity(0.5)
            footer
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
        }
        .frame(width: controller.availableContentSize.width)
        .frame(maxHeight: controller.availableContentSize.height)
        .menoGlass(in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(24)
        .onAppear(perform: focusField)
        .onChange(of: controller.presentation) { _, _ in
            focusField()
        }
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search menu bar items and actions", text: $controller.query)
                .textFieldStyle(.plain)
                .font(.system(size: 21))
                .focused($fieldFocused)
                .onSubmit {
                    controller.activateSelection(secondary: false)
                }
            if !controller.query.isEmpty {
                Button {
                    controller.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(Text("Clear Search"))
                .accessibilityLabel(Text("Clear Search"))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var resultList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(controller.results.enumerated()), id: \.element.id) { index, result in
                        Button {
                            controller.selection = index
                            controller.activateSelection(secondary: false)
                        } label: {
                            switch result {
                            case .item(let item):
                                QuickOpenRow(
                                    item: item,
                                    image: images.image(for: item),
                                    isSelected: index == controller.selection,
                                    shortcut: index < 9 ? index + 1 : nil,
                                    uses: model.usage.usage(of: item.key)?.total ?? 0,
                                    isChanged: changes.changedItems.contains(item.key)
                                )
                            case .command(let command):
                                QuickCommandRow(
                                    command: command,
                                    isSelected: index == controller.selection,
                                    shortcut: index < 9 ? index + 1 : nil
                                )
                            }
                        }
                        .buttonStyle(.plain)
                        .id(result.id)
                        .contentShape(Rectangle())
                        .help(Text(verbatim: title(of: result)))
                        .accessibilityLabel(Text(verbatim: title(of: result)))
                        .accessibilityValue(Text(verbatim: details(of: result)))
                        .accessibilityAddTraits(index == controller.selection ? .isSelected : [])
                        .contextMenu {
                            if case .item(let item) = result {
                                CommandMenuItems(commands: controller.actions(for: item))
                            }
                        }
                        .background {
                            if index == controller.selection {
                                GeometryReader { proxy in
                                    Color.clear.preference(key: SelectedRowFrameKey.self, value: proxy.frame(in: .global))
                                }
                            }
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .padding(6)
            }
            .frame(minHeight: 0, idealHeight: listHeight, maxHeight: listHeight)
            .onPreferenceChange(SelectedRowFrameKey.self) { [controller] frame in
                MainActor.assumeIsolated {
                    controller.selectedRowFrame = frame
                }
            }
            .onChange(of: controller.selection) { _, newValue in
                guard controller.results.indices.contains(newValue) else { return }
                proxy.scrollTo(controller.results[newValue].id)
            }
        }
    }

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                KeyHint(keys: "↩", label: "Open")
                KeyHint(keys: "⌘↩", label: "Secondary click")
                KeyHint(keys: "⌥↩", label: "Show in menu bar")
                KeyHint(keys: "⌘K", label: "Actions")
                Spacer()
                KeyHint(keys: "esc", label: "Close")
            }
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                GridRow {
                    KeyHint(keys: "↩", label: "Open")
                    KeyHint(keys: "esc", label: "Close")
                }
                GridRow {
                    KeyHint(keys: "⌘↩", label: "Secondary click")
                    KeyHint(keys: "⌘K", label: "Actions")
                }
                GridRow {
                    KeyHint(keys: "⌥↩", label: "Show in menu bar")
                        .gridCellColumns(2)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private func title(of result: QuickOpenResult) -> String {
        switch result {
        case .item(let item): return item.displayName
        case .command(let command): return command.title
        }
    }

    private func details(of result: QuickOpenResult) -> String {
        switch result {
        case .item(let item):
            var parts = [item.section.title]
            if item.appName != item.displayName { parts.insert(item.appName, at: 0) }
            if changes.changedItems.contains(item.key) { parts.append(String(localized: "Changed")) }
            return parts.joined(separator: ", ")
        case .command: return String(localized: "Action")
        }
    }

    private func focusField() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000)
            fieldFocused = true
        }
    }
}

/// Where the selected row is, for the actions menu.
private struct SelectedRowFrameKey: PreferenceKey {
    static let defaultValue: CGRect? = nil

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = value ?? nextValue()
    }
}

/// Commands as the entries of a context menu.
struct CommandMenuItems: View {
    let commands: [MoveCommand]

    var body: some View {
        ForEach(Array(commands.enumerated()), id: \.offset) { index, command in
            if command.startsGroup, index > 0 {
                Divider()
            }
            if !command.children.isEmpty {
                Menu {
                    CommandMenuItems(commands: command.children)
                } label: {
                    Label(command.title, systemImage: command.symbol)
                }
            } else if command.isChecked {
                Toggle(isOn: Binding(get: { true }, set: { _ in command.action() })) {
                    Label(command.title, systemImage: command.symbol)
                }
            } else {
                Button(action: command.action) {
                    Label(command.title, systemImage: command.symbol)
                }
                .disabled(!command.isEnabled)
            }
        }
    }
}

private struct QuickOpenRow: View {
    let item: MenuBarItem
    let image: NSImage
    let isSelected: Bool
    let shortcut: Int?
    let uses: Int
    /// The item changed since the person last saw it.
    var isChanged = false

    var body: some View {
        HStack(spacing: 12) {
            Image(menuItemImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)
                .frame(width: 30, height: 30)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(verbatim: item.displayName)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                    if isChanged {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 7, height: 7)
                            .help(Text("Changed since you last looked"))
                            .accessibilityLabel(Text("Changed"))
                    }
                }
                if item.appName != item.displayName {
                    Text(verbatim: item.appName)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if uses > 0 {
                Label("\(uses)", systemImage: "hand.tap")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .labelStyle(.titleAndIcon)
            }
            SectionBadge(section: item.section)
            if let shortcut {
                Text(verbatim: "⌘\(shortcut)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .trailing)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: QuickOpenController.rowHeight - 2)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
        }
    }
}

private struct QuickCommandRow: View {
    let command: QuickCommand
    let isSelected: Bool
    let shortcut: Int?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: command.symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                }
            Text(verbatim: command.title)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("Action")
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .foregroundStyle(.secondary)
                .background {
                    Capsule().fill(Color.primary.opacity(0.08))
                }
            if let shortcut {
                Text(verbatim: "⌘\(shortcut)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .trailing)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: QuickOpenController.rowHeight - 2)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
        }
    }
}

/// A small colored capsule naming an item's section.
struct SectionBadge: View {
    let section: ItemSection

    var body: some View {
        Text(section.title)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(section.color)
            .background {
                Capsule().fill(section.color.opacity(0.14))
            }
    }
}

struct KeyHint: View {
    let keys: String
    let label: LocalizedStringKey

    var body: some View {
        HStack(spacing: 5) {
            Text(verbatim: keys)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                }
            Text(label)
                .font(.system(size: 11))
        }
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: true, vertical: false)
    }
}
