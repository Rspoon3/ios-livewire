import LWModels
import SwiftUI

struct DashboardView: View {
    @State private var viewModel: DashboardViewModel

    init(model: AppModel) {
        _viewModel = State(initialValue: DashboardViewModel(app: model))
    }

    var body: some View {
        List {
            if viewModel.showsEmptyState {
                ContentUnavailableView(
                    "No bikes",
                    systemImage: "bicycle",
                    description: Text("This account has no bikes yet. Add one in the LiveWire app, then pull to refresh.")
                )
            }
            ForEach(viewModel.rows) { row in
                NavigationLink {
                    if row.bike.isPaired == true {
                        BikeDetailView(viewModel: viewModel.detailModel(for: row.bike))
                    } else {
                        PairingView(viewModel: viewModel.pairingModel(for: row.bike))
                    }
                } label: {
                    BikeCard(row: row)
                }
            }
        }
        .navigationTitle("Bikes")
        .refreshable { await viewModel.refresh() }
        .overlay { if viewModel.showsSpinner { ProgressView() } }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if viewModel.isRefreshing { ProgressView() } else {
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await viewModel.refresh() } }
                }
            }
        }
    }
}

private struct BikeCard: View {
    let row: BikeRow

    var body: some View {
        HStack(spacing: 16) {
            BatteryRing(level: row.status?.batteryLevel, isCharging: row.status?.isCharging ?? false)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.bike.displayName).font(.headline)
                switch row.state {
                case .needsPairing:
                    Label("Not paired. Tap to pair.", systemImage: "link.badge.plus")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                case .problem(let message):
                    Text(message).font(.subheadline).foregroundStyle(.red).lineLimit(2)
                case .reading(let status):
                    Text(DashboardViewModel.statusLine(status)).font(.subheadline).foregroundStyle(.secondary)
                    Text("Updated \(status.fetchedAt, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                case .loading:
                    Text("Loading…").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
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
                Text(level.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "–").font(.headline.monospacedDigit())
                if isCharging { Image(systemName: "bolt.fill").font(.caption2).foregroundStyle(.green) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery")
        .accessibilityValue(level.map { Display.percent($0) + (isCharging ? ", charging" : "") } ?? "unknown")
    }

    private var color: Color {
        guard let level else { return .gray }
        if isCharging { return .green }
        return level < 15 ? .red : level < 30 ? .orange : .accentColor
    }
}
