import LWModels
import SwiftUI

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
            if let error = model.ridesError {
                Section { Text(error).foregroundStyle(.red) }
            }
            if model.rides.isEmpty && !model.isLoadingRides && model.ridesError == nil {
                ContentUnavailableView(
                    "No saved rides",
                    systemImage: "road.lanes",
                    description: Text("Rides you save or plan in the LiveWire app show up here. Totals for every ride are above.")
                )
            }
            ForEach(model.rides) { ride in
                NavigationLink {
                    RideDetailView(ride: ride, model: model)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ride.displayName).font(.headline)
                        HStack(spacing: 8) {
                            if let date = ride.startDate { Text(date.formatted(date: .abbreviated, time: .omitted)) }
                            if let distance = ride.distance { Text(distance.formatted(.number.precision(.fractionLength(0...1)))) }
                            if let type = ride.subType { Text(type.capitalized) }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Rides")
        .refreshable {
            await model.loadRides()
            await model.loadAnalytics()
        }
        .task {
            if model.rides.isEmpty { await model.loadRides() }
            await model.loadAnalytics()
        }
        .overlay { if (model.isLoadingRides || model.isLoadingAnalytics) && model.rides.isEmpty && model.analytics.isEmpty { ProgressView() } }
    }
}

/// Shows the ride as the backend returned it. The ride response shape is not mapped yet, so the raw
/// JSON is the honest view; it is also in the log file.
struct RideDetailView: View {
    let ride: RideSummary
    let model: AppModel
    @State private var detail: JSONValue?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("The ride fields are not mapped yet. This is the raw response.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let error { Text(error).foregroundStyle(.red) }
                Text((detail ?? ride.raw).prettyString)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            .padding()
        }
        .navigationTitle(ride.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do { detail = try await model.loadRide(id: ride.id) } catch { self.error = error.localizedDescription }
        }
    }
}
