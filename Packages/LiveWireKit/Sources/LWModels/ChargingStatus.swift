import Foundation

/// Battery and charging state of one bike, as reported by `bikes/{id}/charging/status`.
public struct ChargingStatus: Codable, Sendable, Hashable {
    public var bikeID: String
    /// State of charge, percent (0...100).
    public var batteryLevel: Double?
    public var isCharging: Bool
    public var isPluggedIn: Bool
    /// Charge limit, percent.
    public var chargeLimit: Int?
    /// Time until the charge limit is reached.
    public var timeToLimit: Duration?
    public var range: Measurement<UnitLength>?
    public var odometer: Measurement<UnitLength>?
    /// How old the bike's own report was when the backend answered.
    public var dataAge: Duration?
    /// SAFE, STOLEN or PENDING.
    public var trackingStatus: String?
    /// When this app fetched the status.
    public var fetchedAt: Date

    public init(
        bikeID: String,
        batteryLevel: Double? = nil,
        isCharging: Bool = false,
        isPluggedIn: Bool = false,
        chargeLimit: Int? = nil,
        timeToLimit: Duration? = nil,
        range: Measurement<UnitLength>? = nil,
        odometer: Measurement<UnitLength>? = nil,
        dataAge: Duration? = nil,
        trackingStatus: String? = nil,
        fetchedAt: Date = Date()
    ) {
        self.bikeID = bikeID
        self.batteryLevel = batteryLevel
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.chargeLimit = chargeLimit
        self.timeToLimit = timeToLimit
        self.range = range
        self.odometer = odometer
        self.dataAge = dataAge
        self.trackingStatus = trackingStatus
        self.fetchedAt = fetchedAt
    }

    /// How old a report is, from the amount and unit the backend sends. Units seen on a real bike:
    /// `seconds` and `minute` (singular). Unknown units give `nil`.
    public static func age(amount: Double?, unit: String?) -> Duration? {
        guard let amount, let unit = unit?.lowercased() else { return nil }
        let unitDuration: UnitDuration
        if unit.hasPrefix("sec") {
            unitDuration = .seconds
        } else if unit.hasPrefix("min") {
            unitDuration = .minutes
        } else if unit.hasPrefix("hour") || unit.hasPrefix("hr") {
            unitDuration = .hours
        } else {
            return nil
        }
        return Duration(Measurement(value: amount, unit: unitDuration))
    }
}

extension Duration {
    /// A duration from a `Measurement`, converted by Foundation instead of by hand.
    public init(_ measurement: Measurement<UnitDuration>) {
        self = .seconds(measurement.converted(to: .seconds).value)
    }
}
