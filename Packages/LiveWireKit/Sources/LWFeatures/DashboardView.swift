import LWModels
import SwiftUI

struct DashboardView: View {
    let model: AppModel

    var body: some View {
        List {
            if model.snapshot.bikes.isEmpty && !model.isRefreshing {
                ContentUnavailableView(
                    "No bikes",
                    systemImage: "bicycle",
                    description: Text("This account has no bikes yet. Add one in the LiveWire app, then pull to refresh.")
                )
            }
            ForEach(model.snapshot.bikes) { bike in
                BikeCard(
                    bike: bike,
                    status: model.snapshot.statuses[bike.id],
                    problem: model.statusErrors[bike.id],
                    model: model
                )
            }
        }
        .navigationTitle("Bikes")
        .refreshable { await model.refresh() }
        .overlay { if model.isRefreshing && model.snapshot.bikes.isEmpty { ProgressView() } }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if model.isRefreshing { ProgressView() } else {
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                }
            }
        }
    }
}

private struct BikeCard: View {
    let bike: Bike
    let status: ChargingStatus?
    let problem: String?
    let model: AppModel

    var body: some View {
        if bike.isPaired == true {
            NavigationLink {
                BikeDetailView(bike: bike, status: status, problem: problem, model: model)
            } label: { summary }
        } else {
            NavigationLink {
                PairingView(bike: bike, model: model)
            } label: { summary }
        }
    }

    private var summary: some View {
        HStack(spacing: 16) {
            BatteryRing(level: status?.batteryLevel, isCharging: status?.isCharging ?? false)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(bike.displayName).font(.headline)
                if bike.isPaired != true {
                    Label("Not paired. Tap to pair.", systemImage: "link.badge.plus")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                } else if let problem {
                    Text(problem).font(.subheadline).foregroundStyle(.red).lineLimit(2)
                } else if let status {
                    Text(statusLine(status)).font(.subheadline).foregroundStyle(.secondary)
                    Text("Updated \(status.fetchedAt, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("Loading…").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func statusLine(_ status: ChargingStatus) -> String {
        var parts: [String] = []
        if status.isCharging { parts.append("Charging") } else if status.isPluggedIn { parts.append("Plugged in") }
        if let range = status.rangeMiles {
            parts.append(Measurement(value: range, unit: UnitLength.miles).formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0)))))
        }
        return parts.isEmpty ? "No data" : parts.joined(separator: " · ")
    }
}

struct BatteryRing: View {
    let level: Double?
    let isCharging: Bool

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 7)
            Circle()
                .trim(from: 0, to: min(max((level ?? 0) / 100, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(level.map { "\(Int($0.rounded()))" } ?? "–").font(.headline.monospacedDigit())
                if isCharging { Image(systemName: "bolt.fill").font(.caption2).foregroundStyle(.green) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery")
        .accessibilityValue(level.map { "\(Int($0.rounded())) percent" + (isCharging ? ", charging" : "") } ?? "unknown")
    }

    private var color: Color {
        guard let level else { return .gray }
        if isCharging { return .green }
        return level < 15 ? .red : level < 30 ? .orange : .accentColor
    }
}
