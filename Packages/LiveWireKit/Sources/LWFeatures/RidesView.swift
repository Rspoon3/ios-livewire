import SwiftUI

/// Ride and charging totals for each paired bike.
struct RidesView: View {
    @State private var viewModel: RidesViewModel

    init(model: AppModel) {
        _viewModel = State(initialValue: RidesViewModel(app: model))
    }

    var body: some View {
        List {
            ForEach(viewModel.sections) { section in
                AnalyticsSection(viewModel: viewModel, section: section)
            }
        }
        .navigationTitle("Rides")
        .refreshable { await viewModel.load() }
        .task { await viewModel.load() }
        .overlay {
            if viewModel.isEmpty {
                if viewModel.isLoading {
                    ProgressView()
                } else {
                    ContentUnavailableView(
                        "No ride data",
                        systemImage: "road.lanes",
                        description: Text("Pair a bike to see its ride and charging totals.")
                    )
                }
            }
        }
    }
}
