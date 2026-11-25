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
    /// Minutes until the charge limit is reached.
    public var minutesToLimit: Double?
    public var rangeMiles: Double?
    public var odometerMiles: Double?
    /// How old the bike's own report was when the backend answered.
    public var dataAge: TimeInterval?
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
        minutesToLimit: Double? = nil,
        rangeMiles: Double? = nil,
        odometerMiles: Double? = nil,
        dataAge: TimeInterval? = nil,
        trackingStatus: String? = nil,
        fetchedAt: Date = Date()
    ) {
        self.bikeID = bikeID
        self.batteryLevel = batteryLevel
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.chargeLimit = chargeLimit
        self.minutesToLimit = minutesToLimit
        self.rangeMiles = rangeMiles
        self.odometerMiles = odometerMiles
        self.dataAge = dataAge
        self.trackingStatus = trackingStatus
        self.fetchedAt = fetchedAt
    }

    /// Parses the response body of `bikes/{id}/charging/status`.
    public init(bikeID: String, json: JSONValue, fetchedAt: Date = Date()) {
        let data = json["bikeChargingData"] ?? .null
        self.init(
            bikeID: bikeID,
            batteryLevel: data["batteryPercentage"]?.doubleValue,
            isCharging: data["chargingStatus"]?.boolValue ?? false,
            isPluggedIn: data["pluggedIn"]?.boolValue ?? false,
            chargeLimit: data["maxLimit"]?.intValue.flatMap { $0 == 0 ? nil : $0 },
            minutesToLimit: data["timeToMaxLimit"]?.doubleValue,
            rangeMiles: data["range"]?.doubleValue,
            odometerMiles: data["odometer"]?.doubleValue,
            dataAge: Self.age(
                amount: data["durationElapsed"]?.doubleValue,
                unit: data["durationUnit"]?.textValue
            ),
            trackingStatus: json["trackingStatus"]?.textValue,
            fetchedAt: fetchedAt
        )
    }

    public var rangeKilometers: Double? { rangeMiles.map { $0 * 1.609344 } }
    public var odometerKilometers: Double? { odometerMiles.map { $0 * 1.609344 } }

    /// Units seen on a real bike: `seconds` and `minute` (singular). Unknown units yield `nil`.
    static func age(amount: Double?, unit: String?) -> TimeInterval? {
        guard let amount, let unit = unit?.lowercased() else { return nil }
        if unit.hasPrefix("sec") { return amount }
        if unit.hasPrefix("min") { return amount * 60 }
        if unit.hasPrefix("hour") || unit.hasPrefix("hr") { return amount * 3600 }
        if unit.hasPrefix("day") { return amount * 86_400 }
        return nil
    }
}
