import Foundation
import LWModels
import Observation

/// Ride and charging totals for each paired bike, for one period at a time.
@MainActor
@Observable
final class RidesViewModel {
    struct BikeSection: Identifiable {
        let bike: Bike
        let report: AnalyticsReport
        var id: String { bike.id }
    }

    struct ChartPoint: Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    var period = AnalyticsPeriod.month
    private let app: AppModel

    init(app: AppModel) {
        self.app = app
    }

    var sections: [BikeSection] {
        app.pairedBikes.compactMap { bike in
            app.analytics[bike.id].map { BikeSection(bike: bike, report: $0) }
        }
    }

    var isLoading: Bool { app.isLoadingAnalytics }
    var isEmpty: Bool { app.analytics.isEmpty }

    func load() async { await app.loadAnalytics() }

    // MARK: Rides

    func rideRows(_ report: AnalyticsReport) -> [DetailRow] {
        guard let totals = report.rides?.period(period)?.totals else { return [] }
        var rows = [
            DetailRow(title: "Rides", value: "\(totals.rideCount)"),
            DetailRow(title: "Distance", value: Display.distance(totals.distance)),
            DetailRow(title: "Riding time", value: Display.duration(totals.duration)),
        ]
        if let efficiency = totals.energyPer100Miles {
            rows.append(DetailRow(title: "Efficiency", value: Display.energy(efficiency, fractionDigits: 1) + " / 100 mi"))
        }
        rows.append(DetailRow(title: "Battery used", value: Display.percent(totals.batteryUsedPercent)))
        return rows
    }

    func distanceChart(_ report: AnalyticsReport) -> [ChartPoint] {
        report.rides?.period(period)?.buckets.compactMap { bucket in
            bucket.start.map { ChartPoint(date: $0, value: bucket.distance.value) }
        } ?? []
    }

    // MARK: Charging

    func chargingRows(_ report: AnalyticsReport) -> [DetailRow] {
        guard let totals = report.charging?.period(period)?.totals else { return [] }
        return [
            DetailRow(title: "Sessions", value: "\(totals.sessionCount)"),
            DetailRow(title: "Energy added", value: Display.energy(totals.energyAdded)),
            DetailRow(title: "Time charging", value: Display.duration(totals.chargeTime)),
        ]
    }

    func energyChart(_ report: AnalyticsReport) -> [ChartPoint] {
        report.charging?.period(period)?.buckets.compactMap { bucket in
            bucket.start.map { ChartPoint(date: $0, value: bucket.energyAdded.value) }
        } ?? []
    }

    /// The bar width: one day, week or month per bar.
    func calendarUnit(_ report: AnalyticsReport) -> Calendar.Component {
        let size = report.rides?.period(period)?.bucketSize ?? report.charging?.period(period)?.bucketSize
        switch size {
        case .day, nil: return .day
        case .week: return .weekOfYear
        case .month: return .month
        }
    }
}
