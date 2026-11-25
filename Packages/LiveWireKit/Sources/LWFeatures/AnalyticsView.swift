import Charts
import LWModels
import SwiftUI

/// Ride and charging totals for one bike, with a period picker and a bar chart per topic.
struct AnalyticsSection: View {
    let bike: Bike
    let report: AnalyticsReport
    @Binding var period: AnalyticsPeriod

    var body: some View {
        Section {
            Picker("Period", selection: $period) {
                ForEach(AnalyticsPeriod.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        } header: {
            Text(bike.displayName)
        }

        if let error = report.ridesError { Section { Text(error).foregroundStyle(.red) } }
        if let rides = report.rides?.period(period) { RideSection(period: rides) }

        if let error = report.chargingError { Section { Text(error).foregroundStyle(.red) } }
        if let charging = report.charging?.period(period) { ChargingSection(period: charging) }
    }
}

private struct RideSection: View {
    let period: RideAnalyticsPeriod

    var body: some View {
        Section("Rides") {
            LabeledContent("Rides", value: "\(period.totals.rideCount)")
            LabeledContent("Distance", value: miles(period.totals.distanceMiles))
            LabeledContent("Riding time", value: duration(period.totals.durationSeconds))
            if let efficiency = period.totals.efficiencyWhPerMile {
                LabeledContent("Efficiency", value: "\(Int(efficiency.rounded())) Wh/mi")
            }
            LabeledContent("Battery used", value: "\(Int(period.totals.batteryUsedPercent.rounded()))%")
            BucketChart(
                points: period.buckets.compactMap { bucket in bucket.start.map { ($0, bucket.distanceMiles) } },
                granularity: period.bucketSize,
                unit: "mi"
            )
        }
    }
}

private struct ChargingSection: View {
    let period: ChargingAnalyticsPeriod

    var body: some View {
        Section("Charging") {
            LabeledContent("Sessions", value: "\(period.totals.sessionCount)")
            LabeledContent("Energy added", value: "\(Int(period.totals.energyAddedKWh.rounded())) kWh")
            LabeledContent("Time charging", value: duration(period.totals.chargeTimeSeconds))
            BucketChart(
                points: period.buckets.compactMap { bucket in bucket.start.map { ($0, bucket.energyAddedKWh) } },
                granularity: period.bucketSize,
                unit: "kWh"
            )
        }
    }
}

private struct BucketChart: View {
    let points: [(Date, Double)]
    let granularity: AnalyticsGranularity?
    let unit: String

    var body: some View {
        Chart(points, id: \.0) { point in
            BarMark(x: .value("Date", point.0, unit: calendarUnit), y: .value(unit, point.1))
        }
        .chartYAxisLabel(unit)
        .frame(height: 140)
        .padding(.vertical, 4)
    }

    private var calendarUnit: Calendar.Component {
        switch granularity {
        case .day, nil: .day
        case .week: .weekOfYear
        case .month: .month
        }
    }
}

private func miles(_ value: Double) -> String {
    Measurement(value: value, unit: UnitLength.miles)
        .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
}

private func duration(_ seconds: Double) -> String {
    Duration.seconds(seconds).formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated, maximumUnitCount: 2))
}
