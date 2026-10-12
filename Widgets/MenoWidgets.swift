import AppIntents
import MenoCore
import SwiftUI
import WidgetKit

struct MenuActionsConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Menu bar actions"
    @Parameter(title: "First scene name") var firstScene: String?
    @Parameter(title: "Second scene name") var secondScene: String?
}

struct MenuActionsEntry: TimelineEntry {
    let date: Date
    let firstScene: String?
    let secondScene: String?
}

struct MenuActionsProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> MenuActionsEntry {
        MenuActionsEntry(date: Date(), firstScene: nil, secondScene: nil)
    }

    func snapshot(for configuration: MenuActionsConfiguration, in context: Context) async -> MenuActionsEntry {
        MenuActionsEntry(date: Date(), firstScene: configuration.firstScene, secondScene: configuration.secondScene)
    }

    func timeline(for configuration: MenuActionsConfiguration, in context: Context) async -> Timeline<MenuActionsEntry> {
        Timeline(entries: [await snapshot(for: configuration, in: context)], policy: .never)
    }
}

struct MenuActionsView: View {
    let entry: MenuActionsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Meno", systemImage: "menubar.rectangle").font(.headline)
            HStack(spacing: 8) {
                action("Show icons", symbol: "eye", command: .show(all: false))
                action("Hide icons", symbol: "eye.slash", command: .hide)
            }
            HStack(spacing: 8) {
                action("Zen on", symbol: "leaf.fill", command: .zen(true))
                action("Zen off", symbol: "leaf", command: .zen(false))
            }
            HStack(spacing: 8) {
                scene(entry.firstScene)
                scene(entry.secondScene)
            }
        }
        .containerBackground(.background, for: .widget)
        .widgetURL(LinkCommand.settings(pane: "scenes").url)
    }

    private func action(_ title: LocalizedStringKey, symbol: String, command: LinkCommand) -> some View {
        Link(destination: command.url!) {
            Label(title, systemImage: symbol).font(.caption).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 7).padding(.vertical, 5)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain)
    }

    @ViewBuilder private func scene(_ name: String?) -> some View {
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Link(destination: LinkCommand.scene(name: name.trimmingCharacters(in: .whitespacesAndNewlines)).url!) {
                HStack(spacing: 4) {
                    Image(systemName: "rectangle.3.group")
                    Text(verbatim: name).lineLimit(1)
                }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
        } else {
            Link(destination: LinkCommand.settings(pane: "scenes").url!) {
                Text("Configure scenes").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
        }
    }
}

@main
struct MenoWidgets: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "MenoActions", intent: MenuActionsConfiguration.self, provider: MenuActionsProvider()) {
            MenuActionsView(entry: $0)
        }
        .configurationDisplayName("Menu bar actions")
        .description("Apply a scene, show or hide icons, or turn Zen on and off.")
        .supportedFamilies([.systemMedium])
    }
}
