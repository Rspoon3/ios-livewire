import SwiftUI
import WidgetKit
import LWModels

public struct BatteryWidget: Widget {
    public static let kind = "BikeBatteryWidget"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: BatteryProvider()) { entry in
            BatteryWidgetView(entry: entry)
        }
        .configurationDisplayName("Bike battery")
        .description("Battery level and charging state of your bike. With several bikes, choose the one to show in the app.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct BatteryWidgetView: View {
    let entry: BatteryEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder private var content: some View {
        switch entry.state {
        case .ok: reading
        case .signedOut: message("Sign in", "Open the app to sign in.")
        case .noBike: message("No bike", "Add a bike in the LiveWire app.")
        case .notPaired: message("Not paired", "Open the app to pair \(entry.bikeName).")
        case .failed(let reason): message("Can't update", reason)
        }
    }

    // MARK: Reading

    @ViewBuilder private var reading: some View {
        let level = entry.batteryLevel
        switch family {
        case .accessoryCircular:
            Gauge(value: (level ?? 0) / 100) {
                Image(systemName: entry.status?.isCharging == true ? "bolt.fill" : "battery.100")
            } currentValueLabel: {
                Text(level.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "–")
            }
            .gaugeStyle(.accessoryCircular)

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.bikeName).font(.headline).lineLimit(1)
                Gauge(value: (level ?? 0) / 100) { Text("Battery") }
                    .gaugeStyle(.accessoryLinearCapacity)
                Text(summaryLine).font(.caption)
            }

        case .accessoryInline:
            Text("\(entry.status?.isCharging == true ? "⚡︎ " : "")\(level.map { Display.percent($0) } ?? "–") \(entry.bikeName)")

        case .systemMedium:
            HStack(spacing: 16) {
                ring(level: level).frame(width: 96, height: 96)
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.bikeName).font(.headline).lineLimit(1)
                    Text(summaryLine).font(.subheadline).foregroundStyle(.secondary)
                    if let limit = entry.status?.chargeLimit { Text("Limit \(limit)%").font(.caption).foregroundStyle(.secondary) }
                    freshness
                }
                Spacer(minLength: 0)
            }

        default:
            VStack(spacing: 6) {
                Text(entry.bikeName).font(.caption.bold()).lineLimit(1)
                ring(level: level).frame(width: 78, height: 78)
                Text(summaryLine).font(.caption2).foregroundStyle(.secondary)
                freshness
            }
        }
    }

    private func ring(level: Double?) -> some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 8)
            Circle()
                .trim(from: 0, to: min(max((level ?? 0) / 100, 0), 1))
                .stroke(color(level), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(level.map { Display.percent($0) } ?? "–").font(.title3.bold().monospacedDigit())
                if entry.status?.isCharging == true { Image(systemName: "bolt.fill").font(.caption2).foregroundStyle(.green) }
            }
        }
    }

    private var summaryLine: String {
        guard let status = entry.status else { return "" }
        var parts: [String] = []
        if status.isCharging { parts.append("Charging") } else if status.isPluggedIn { parts.append("Plugged in") }
        if let range = status.range { parts.append(Display.distance(range)) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var freshness: some View {
        if let fetched = entry.status?.fetchedAt {
            Text(entry.isStale ? "Offline · \(fetched, style: .relative)" : "\(fetched, style: .relative) ago")
                .font(.caption2)
                .foregroundStyle(entry.isStale ? Color.orange : Color.secondary.opacity(0.7))
        }
    }

    private func color(_ level: Double?) -> Color {
        guard let level else { return .gray }
        if entry.status?.isCharging == true { return .green }
        return level < 15 ? .red : level < 30 ? .orange : .accentColor
    }

    private func message(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            if family != .accessoryInline { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
        }
    }
}

/// Widget bundle contents, so the extension target only has to name this type.
public struct LiveWireWidgets: WidgetBundle {
    public init() {}

    public var body: some Widget {
        BatteryWidget()
    }
}
