import Charts
import LWModels
import SwiftUI

/// Ride and charging totals for one bike, with a period picker and a bar chart per topic.
struct AnalyticsSection: View {
    @Bindable var viewModel: RidesViewModel
    let section: RidesViewModel.BikeSection

    var body: some View {
        Section {
            Picker("Period", selection: $viewModel.period) {
                ForEach(AnalyticsPeriod.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        } header: {
            Text(section.bike.displayName)
        }

        if let error = section.report.ridesError { Section { Text(error).foregroundStyle(.red) } }
        let rideRows = viewModel.rideRows(section.report)
        if !rideRows.isEmpty {
            Section("Rides") {
                ForEach(rideRows) { LabeledContent($0.title, value: $0.value) }
                BucketChart(points: viewModel.distanceChart(section.report), unit: "mi", component: viewModel.calendarUnit(section.report))
            }
        }

        if let error = section.report.chargingError { Section { Text(error).foregroundStyle(.red) } }
        let chargingRows = viewModel.chargingRows(section.report)
        if !chargingRows.isEmpty {
            Section("Charging") {
                ForEach(chargingRows) { LabeledContent($0.title, value: $0.value) }
                BucketChart(points: viewModel.energyChart(section.report), unit: "kWh", component: viewModel.calendarUnit(section.report))
            }
        }
    }
}

private struct BucketChart: View {
    let points: [RidesViewModel.ChartPoint]
    let unit: String
    let component: Calendar.Component

    var body: some View {
        Chart(points) { point in
            BarMark(x: .value("Date", point.date, unit: component), y: .value(unit, point.value))
        }
        .chartYAxisLabel(unit)
        .frame(height: 140)
        .padding(.vertical, 4)
    }
}
