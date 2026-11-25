import Foundation
import LWModels
import WidgetKit

struct BatteryEntry: TimelineEntry {
    enum State: Equatable {
        case ok
        case signedOut
        case noBike
        case notPaired
        /// The fetch failed and there is no earlier reading to fall back on.
        case failed(String)
    }

    let date: Date
    let bikeName: String
    let state: State
    let status: ChargingStatus?
    /// True when `status` is an older reading shown because the fetch failed.
    let isStale: Bool

    var batteryLevel: Double? { status?.batteryLevel }

    static let placeholder = BatteryEntry(
        date: .now,
        bikeName: "My bike",
        state: .ok,
        status: ChargingStatus(bikeID: "0", batteryLevel: 76, isCharging: false, rangeMiles: 98),
        isStale: false
    )

    static func message(_ state: State, bikeName: String = "LiveWire") -> BatteryEntry {
        BatteryEntry(date: .now, bikeName: bikeName, state: state, status: nil, isStale: false)
    }
}
