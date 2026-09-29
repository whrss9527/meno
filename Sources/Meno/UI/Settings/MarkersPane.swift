import MenoCore
import SwiftUI

struct MarkersPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            SettingsCard("Markers", symbol: "rectangle.split.3x1", footnote: "New markers appear at the left end of the menu bar. Hold ⌘ and drag them where you want them, or use the Layout pane.") {
                HStack(spacing: 14) {
                    MarkerPreview(kind: .space)
                    MarkerPreview(kind: .line)
                    MarkerPreview(kind: .dot)
                    MarkerPreview(kind: .symbol)
                    MarkerPreview(kind: .text)
                }
                Text("Markers are small items you add to the menu bar to group other items: some space, a thin line, a dot, a symbol or a short label such as “Work”.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Menu {
                    ForEach(MarkerKind.allCases, id: \.self) { kind in
                        Button {
                            add(kind)
                        } label: {
                            Label(kind.title, systemImage: kind.symbol)
                        }
                    }
                } label: {
                    Label("Add Marker", systemImage: "plus")
                }
                .fixedSize()
            }

            ForEach($model.settings.markers) { $marker in
                MarkerRow(marker: $marker) {
                    model.settings.markers.removeAll { $0.id == marker.id }
                }
            }
        }
    }

    private func add(_ kind: MarkerKind) {
        var marker = MenuMarker(kind: kind)
        switch kind {
        case .text: marker.text = String(localized: "Work")
        case .symbol: marker.symbol = "star.fill"
        case .space: marker.width = 16
        default: break
        }
        model.settings.markers.append(marker)
    }
}

private struct MarkerPreview: View {
    let kind: MarkerKind

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: kind.symbol)
                .font(.system(size: 14))
                .frame(width: 34, height: 26)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                }
            Text(verbatim: kind.title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

private struct MarkerRow: View {
    @Binding var marker: MenuMarker
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: marker.kind.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .background { Circle().fill(Color.accentColor.opacity(0.14)) }
            Picker("Kind", selection: $marker.kind) {
                ForEach(MarkerKind.allCases, id: \.self) { kind in
                    Text(verbatim: kind.title).tag(kind)
                }
            }
            .labelsHidden()
            .frame(width: 110)
            switch marker.kind {
            case .space:
                Slider(value: $marker.width, in: 4...80, step: 2) {
                    Text("Width")
                }
                .labelsHidden()
                .frame(width: 180)
                .accessibilityValue(Text(verbatim: "\(Int(marker.width)) pt"))
                Text(verbatim: "\(Int(marker.width)) pt")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            case .symbol:
                TextField("SF Symbol name", text: $marker.symbol)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                Image(systemName: marker.symbol)
            case .text:
                TextField("Label", text: $marker.text)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
            case .line, .dot:
                Text("Nothing to set")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .menoGlassCard(cornerRadius: 16)
    }
}
