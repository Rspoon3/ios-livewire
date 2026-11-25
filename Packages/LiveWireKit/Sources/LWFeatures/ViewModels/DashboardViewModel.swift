import Foundation
import LWModels
import Observation

/// One bike on the dashboard.
struct BikeRow: Identifiable {
    enum State {
        /// This device is not paired with the bike yet.
        case needsPairing
        /// The last status request failed.
        case problem(String)
        case reading(ChargingStatus)
        case loading
    }

    let bike: Bike
    let state: State

    var id: String { bike.id }

    var status: ChargingStatus? {
        if case .reading(let status) = state { status } else { nil }
    }
}

@MainActor
@Observable
final class DashboardViewModel {
    private let app: AppModel

    init(app: AppModel) {
        self.app = app
    }

    var rows: [BikeRow] {
        app.snapshot.bikes.map { bike in
            let state: BikeRow.State
            if bike.isPaired != true {
                state = .needsPairing
            } else if let problem = app.statusErrors[bike.id] {
                state = .problem(problem)
            } else if let status = app.snapshot.statuses[bike.id] {
                state = .reading(status)
            } else {
                state = .loading
            }
            return BikeRow(bike: bike, state: state)
        }
    }

    var isRefreshing: Bool { app.isRefreshing }
    var showsEmptyState: Bool { app.snapshot.bikes.isEmpty && !app.isRefreshing }
    var showsSpinner: Bool { app.snapshot.bikes.isEmpty && app.isRefreshing }

    func refresh() async { await app.refresh() }

    func detailModel(for bike: Bike) -> BikeDetailViewModel { BikeDetailViewModel(bikeID: bike.id, app: app) }
    func pairingModel(for bike: Bike) -> PairingViewModel { PairingViewModel(bike: bike, pairing: app) }

    /// "Charging · 73 mi", for the line under a bike's name.
    static func statusLine(_ status: ChargingStatus) -> String {
        var parts: [String] = []
        if status.isCharging { parts.append("Charging") } else if status.isPluggedIn { parts.append("Plugged in") }
        if let range = status.range { parts.append(Display.distance(range)) }
        return parts.isEmpty ? "No data" : parts.joined(separator: " · ")
    }
}
