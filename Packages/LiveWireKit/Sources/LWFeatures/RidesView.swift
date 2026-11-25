import LWModels
import SwiftUI

/// Ride and charging totals for each paired bike.
struct RidesView: View {
    let model: AppModel
    @State private var period = AnalyticsPeriod.month

    var body: some View {
        List {
            ForEach(model.snapshot.pairedBikes) { bike in
                if let report = model.analytics[bike.id] {
                    AnalyticsSection(bike: bike, report: report, period: $period)
                }
            }
        }
        .navigationTitle("Rides")
        .refreshable { await model.loadAnalytics() }
        .task { await model.loadAnalytics() }
        .overlay {
            if model.analytics.isEmpty {
                if model.isLoadingAnalytics {
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
