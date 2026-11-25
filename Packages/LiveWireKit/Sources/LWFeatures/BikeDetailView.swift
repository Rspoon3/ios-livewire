import LWModels
import SwiftUI

struct BikeDetailView: View {
    let bike: Bike
    let status: ChargingStatus?
    let problem: String?
    let model: AppModel

    var body: some View {
        List {
            Section {
                HStack {
                    Spacer()
                    BatteryRing(level: status?.batteryLevel, isCharging: status?.isCharging ?? false)
                        .frame(width: 140, height: 140)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            if let problem {
                Section { Text(problem).foregroundStyle(.red) }
            }

            if let status {
                Section("Charging") {
                    row("State", status.isCharging ? "Charging" : status.isPluggedIn ? "Plugged in" : "Not charging")
                    if let limit = status.chargeLimit { row("Charge limit", "\(limit)%") }
                    if let minutes = status.minutesToLimit, status.isCharging, minutes > 0 {
                        row("Time to limit", Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                    }
                }
                Section("Bike") {
                    if let miles = status.rangeMiles { row("Range", distance(miles)) }
                    if let miles = status.odometerMiles { row("Odometer", distance(miles)) }
                    if let age = status.dataAge {
                        row("Bike reported", Duration.seconds(age).formatted(.units(allowed: [.days, .hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 1)) + " before the fetch")
                    }
                    if let tracking = status.trackingStatus { row("Tracking", tracking.capitalized) }
                }
                Section {
                    row("Fetched", status.fetchedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }

            Section("Bike details") {
                row("Name", bike.displayName)
                if let vin = bike.vin { row("VIN", vin) }
                if let year = bike.year { row("Year", String(year)) }
                row("Bike ID", bike.id)
            }

            if model.snapshot.pairedBikes.count > 1 {
                Section {
                    Button("Show this bike in the widget by default") {
                        Task { await model.select(bikeID: bike.id) }
                    }
                } footer: {
                    Text("Widgets can also be set to a specific bike: long-press the widget, then Edit Widget.")
                }
            }
        }
        .navigationTitle(bike.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refresh() }
    }

    private func row(_ title: String, _ value: String) -> some View {
        LabeledContent(title, value: value)
    }

    private func distance(_ miles: Double) -> String {
        Measurement(value: miles, unit: UnitLength.miles)
            .formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0...1))))
    }
}
