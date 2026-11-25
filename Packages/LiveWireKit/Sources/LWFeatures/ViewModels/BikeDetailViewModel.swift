import Foundation
import LWModels
import Observation

@MainActor
@Observable
final class BikeDetailViewModel {
    let bikeID: String
    private let app: AppModel

    init(bikeID: String, app: AppModel) {
        self.bikeID = bikeID
        self.app = app
    }

    var bike: Bike? { app.snapshot.bikes.first { $0.id == bikeID } }
    var title: String { bike?.displayName ?? "Bike" }
    var status: ChargingStatus? { app.snapshot.statuses[bikeID] }
    var problem: String? { app.statusErrors[bikeID] }

    var chargingRows: [DetailRow] {
        guard let status else { return [] }
        var rows = [DetailRow(title: "State", value: status.isCharging ? "Charging" : status.isPluggedIn ? "Plugged in" : "Not charging")]
        if let limit = status.chargeLimit { rows.append(DetailRow(title: "Charge limit", value: Display.percent(Double(limit)))) }
        if let timeToLimit = status.timeToLimit, status.isCharging, timeToLimit > .zero {
            rows.append(DetailRow(title: "Time to limit", value: Display.duration(timeToLimit)))
        }
        return rows
    }

    var bikeRows: [DetailRow] {
        guard let status else { return [] }
        var rows: [DetailRow] = []
        if let range = status.range { rows.append(DetailRow(title: "Range", value: Display.distance(range, fractionDigits: 1))) }
        if let odometer = status.odometer { rows.append(DetailRow(title: "Odometer", value: Display.distance(odometer, fractionDigits: 1))) }
        if let age = status.dataAge {
            rows.append(DetailRow(title: "Bike reported", value: Display.duration(age) + " before the fetch"))
        }
        if let tracking = status.trackingStatus { rows.append(DetailRow(title: "Tracking", value: tracking.capitalized)) }
        return rows
    }

    var fetchedRow: DetailRow? {
        status.map { DetailRow(title: "Fetched", value: $0.fetchedAt.formatted(date: .abbreviated, time: .shortened)) }
    }

    var detailsRows: [DetailRow] {
        guard let bike else { return [] }
        var rows = [DetailRow(title: "Name", value: bike.displayName)]
        if let vin = bike.vin { rows.append(DetailRow(title: "VIN", value: vin)) }
        if let year = bike.year { rows.append(DetailRow(title: "Year", value: String(year))) }
        rows.append(DetailRow(title: "Bike ID", value: bike.id))
        return rows
    }

    /// With more than one paired bike, the widget needs to know which one to show by default.
    var offersWidgetDefault: Bool { app.pairedBikes.count > 1 }

    func useAsWidgetDefault() async { await app.select(bikeID: bikeID) }
    func refresh() async { await app.refresh() }
}
