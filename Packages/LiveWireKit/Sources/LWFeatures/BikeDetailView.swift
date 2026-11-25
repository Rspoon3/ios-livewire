import SwiftUI

struct BikeDetailView: View {
    @State private var viewModel: BikeDetailViewModel

    init(viewModel: BikeDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Spacer()
                    BatteryRing(level: viewModel.status?.batteryLevel, isCharging: viewModel.status?.isCharging ?? false)
                        .frame(width: 140, height: 140)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            if let problem = viewModel.problem {
                Section { Text(problem).foregroundStyle(.red) }
            }

            rows("Charging", viewModel.chargingRows)
            rows("Bike", viewModel.bikeRows)
            if let fetched = viewModel.fetchedRow {
                Section { LabeledContent(fetched.title, value: fetched.value) }
            }
            rows("Bike details", viewModel.detailsRows)

            if viewModel.offersWidgetDefault {
                Section {
                    Button("Show this bike in the widget") {
                        Task { await viewModel.useAsWidgetDefault() }
                    }
                } footer: {
                    Text("The widget shows one bike. This chooses which.")
                }
            }
        }
        .navigationTitle(viewModel.title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.refresh() }
    }

    @ViewBuilder
    private func rows(_ title: String, _ rows: [DetailRow]) -> some View {
        if !rows.isEmpty {
            Section(title) {
                ForEach(rows) { LabeledContent($0.title, value: $0.value) }
            }
        }
    }
}
