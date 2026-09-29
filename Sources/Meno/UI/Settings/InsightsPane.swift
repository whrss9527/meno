import Charts
import MenoCore
import SwiftUI

struct InsightsPane: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var inventory: ItemInventory
    @ObservedObject var images: ItemImageCache

    @State private var confirmingReset = false

    private struct DayCount: Identifiable {
        let date: Date
        let count: Int
        var id: Date { date }
    }

    var body: some View {
        VStack(spacing: 16) {
            if !model.settings.general.usageTracking {
                Banner(
                    symbol: "chart.bar.xaxis",
                    tint: .blue,
                    title: "Usage statistics are off",
                    message: "Turn them on to see which items you use and get suggestions.",
                    actionTitle: "Turn On",
                    action: { model.settings.general.usageTracking = true }
                )
            }
            tiles
            revealChart
            topItems
            suggestions
            HStack {
                Text("Statistics never leave this Mac.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset Statistics…") { confirmingReset = true }
                    .menoGlassButtonStyle()
            }
        }
        .confirmationDialog("Reset usage statistics?", isPresented: $confirmingReset) {
            Button("Reset", role: .destructive) { model.resetUsage() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Tiles

    private var tiles: some View {
        let today = model.usage.dailyReveals(lastDays: 1).first?.count ?? 0
        let week = model.usage.dailyReveals(lastDays: 7).reduce(0) { $0 + $1.count }
        return HStack(spacing: 12) {
            StatTile(value: inventory.items(in: .visible).count, label: "Visible", symbol: ItemSection.visible.symbol, color: ItemSection.visible.color)
            StatTile(value: inventory.items(in: .hidden).count, label: "Hidden", symbol: ItemSection.hidden.symbol, color: ItemSection.hidden.color)
            StatTile(value: inventory.items(in: .stash).count, label: "Stash", symbol: ItemSection.stash.symbol, color: ItemSection.stash.color)
            StatTile(value: today, label: "Reveals today", symbol: "eye", color: .blue)
            StatTile(value: week, label: "This week", symbol: "calendar", color: .teal)
        }
    }

    // MARK: Chart

    private var revealChart: some View {
        let series = model.usage.dailyReveals(lastDays: 14).map { DayCount(date: $0.date, count: $0.count) }
        return SettingsCard("Reveals over the last two weeks", symbol: "chart.bar") {
            Chart(series) { day in
                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("Reveals", day.count)
                )
                .foregroundStyle(Color.accentColor.gradient)
                .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
            .frame(height: 150)
            if !model.usage.revealTriggers.isEmpty {
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(model.usage.revealTriggers.sorted { $0.value > $1.value }, id: \.key) { entry in
                        let title = RevealTrigger(rawValue: entry.key)?.title ?? entry.key
                        Text(verbatim: "\(title) · \(entry.value)")
                            .font(.system(size: 11))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background { Capsule().fill(Color.primary.opacity(0.07)) }
                    }
                }
            }
        }
    }

    // MARK: Top items

    private var topItems: some View {
        let top = model.usage.topItems(limit: 8, lastDays: 30)
        let maximum = max(top.first?.count ?? 1, 1)
        return SettingsCard("Most used in the last 30 days", symbol: "star") {
            if top.isEmpty {
                Text("Open a few items and they will show up here.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            ForEach(top, id: \.key) { entry in
                let item = inventory.item(for: entry.key)
                HStack(spacing: 10) {
                    if let item {
                        Image(nsImage: images.image(for: item))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 18, height: 18)
                    } else {
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(.secondary)
                            .frame(width: 18, height: 18)
                    }
                    Text(verbatim: item?.displayName ?? AppDirectory.name(for: entry.key.owner))
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .frame(width: 180, alignment: .leading)
                    GeometryReader { proxy in
                        Capsule()
                            .fill(Color.accentColor.opacity(0.75))
                            .frame(width: max(proxy.size.width * CGFloat(entry.count) / CGFloat(maximum), 4))
                    }
                    .frame(height: 8)
                    Text(verbatim: "\(entry.count)")
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .frame(width: 34, alignment: .trailing)
                    if let item {
                        SectionBadge(section: item.section)
                    }
                }
            }
        }
    }

    // MARK: Suggestions

    private var suggestions: some View {
        let list = model.usage.suggestions(sections: inventory.sections, movable: inventory.movableKeys)
        return SettingsCard("Suggestions", symbol: "lightbulb", footnote: "Based on how often you open items while they are hidden, and on items you have not used for three weeks.") {
            if list.isEmpty {
                Text("Nothing to suggest right now. Your menu bar looks well arranged.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            ForEach(list, id: \.self) { suggestion in
                let item = inventory.item(for: suggestion.key)
                HStack(spacing: 10) {
                    if let item {
                        Image(nsImage: images.image(for: item))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 18, height: 18)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: item?.displayName ?? suggestion.key.owner)
                            .font(.system(size: 13, weight: .medium))
                        switch suggestion {
                        case .promote(_, let uses):
                            Text("Opened \(uses) times this week while hidden.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        case .demote(_, let days):
                            Text("Not used for \(days) days.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    switch suggestion {
                    case .promote(let key, _):
                        Button("Keep Visible") { model.move(key, to: .visible) }
                            .menoGlassButtonStyle(prominent: true)
                    case .demote(let key, _):
                        Button("Hide") { model.move(key, to: .hidden) }
                            .menoGlassButtonStyle()
                    }
                }
            }
        }
    }
}

private struct StatTile: View {
    let value: Int
    let label: LocalizedStringKey
    let symbol: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
            Text(verbatim: "\(value)")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .menoGlassCard(cornerRadius: 16)
    }
}
