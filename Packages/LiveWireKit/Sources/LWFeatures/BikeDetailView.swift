import MapKit
import SwiftUI

struct BikeDetailView: View {
    @State private var viewModel: BikeDetailViewModel
    @State private var cameraPosition = MapCameraPosition.automatic

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
            locationSection
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
        .task { await viewModel.loadLocation() }
    }

    @ViewBuilder
    private var locationSection: some View {
        if let center = viewModel.mapCenter {
            Section("Location") {
                Map(position: $cameraPosition) {
                    Marker(viewModel.title, systemImage: "bolt.fill", coordinate: center.coordinate)
                }
                .frame(height: 220)
                .clipShape(.rect(cornerRadius: 12))
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                .onChange(of: center, initial: true) { _, center in
                    cameraPosition = .camera(MapCamera(centerCoordinate: center.coordinate, distance: 2_000))
                }

                ForEach(viewModel.locationRows) { LabeledContent($0.title, value: $0.value) }
            }
        } else if let problem = viewModel.locationProblem {
            Section("Location") { Text(problem).foregroundStyle(.red) }
        } else if viewModel.hasNoPosition {
            Section("Location") {
                Text("The bike has not reported a position yet.").foregroundStyle(.secondary)
            }
        }
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
