import Foundation

// Models for `bikes/{id}/ride/analytics` and `bikes/{id}/charging/analytics`.
//
// Both answer with the same envelope: `{bikeId, vin, periods: [...]}`. There are four periods
// (`WEEK`, `MONTH`, `3M`, `6M`), each with `granularity` (`DAY`, `WEEK` or `MONTH`), a list of
// `buckets` and one `summary`. Shapes confirmed against a real account on 2026-11-25.

/// The time range an analytics period covers.
public enum AnalyticsPeriod: String, CaseIterable, Sendable, Hashable, Codable {
    case week = "WEEK"
    case month = "MONTH"
    case threeMonths = "3M"
    case sixMonths = "6M"

    public var title: String {
        switch self {
        case .week: "Week"
        case .month: "Month"
        case .threeMonths: "3 months"
        case .sixMonths: "6 months"
        }
    }
}

/// How a period is split into buckets.
public enum AnalyticsGranularity: String, Sendable, Hashable, Codable {
    case day = "DAY"
    case week = "WEEK"
    case month = "MONTH"
}

enum AnalyticsParsing {
    /// Bucket starts are plain dates (`2026-11-01`). They become midnight in the current calendar.
    static func day(_ text: String?) -> Date? {
        guard let text else { return nil }
        let parts = text.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func periods<Period>(_ json: JSONValue, make: (JSONValue) -> Period?) -> [Period]? {
        json["periods"]?.arrayValue?.compactMap(make)
    }
}

// MARK: Rides

public struct RideBucket: Sendable, Hashable, Identifiable {
    public var id: String { startText }
    public var startText: String
    public var start: Date?
    public var rideCount: Int
    public var batteryUsedPercent: Double
    /// Miles. Not stated by the backend. Inferred from the numbers: with miles, the energy per
    /// 100% battery works out to about 10.3 kWh, matching the charging data and the bike's pack size.
    public var distanceMiles: Double
    /// kWh per kilometre (the field name says so). `nil` when the bucket has no rides.
    public var efficiencyKWhPerKm: Double?

    init(json: JSONValue) {
        startText = json["bucketStart"]?.textValue ?? ""
        start = AnalyticsParsing.day(startText)
        rideCount = json["rideCount"]?.intValue ?? 0
        batteryUsedPercent = json["sumBatteryUsedPercent"]?.doubleValue ?? 0
        distanceMiles = json["totalDistance"]?.doubleValue ?? 0
        efficiencyKWhPerKm = json["totalEfficiencykWhPerKm"]?.doubleValue
    }
}

public struct RideTotals: Sendable, Hashable {
    public var rideCount: Int
    public var batteryUsedPercent: Double
    public var distanceMiles: Double
    public var durationSeconds: Double
    public var efficiencyKWhPerKm: Double?

    init(json: JSONValue) {
        rideCount = json["rideCount"]?.intValue ?? 0
        batteryUsedPercent = json["totalBatteryUsedPercent"]?.doubleValue ?? 0
        distanceMiles = json["totalDistance"]?.doubleValue ?? 0
        durationSeconds = json["totalDurationSeconds"]?.doubleValue ?? 0
        efficiencyKWhPerKm = json["totalEfficiencykWhPerKm"]?.doubleValue
    }

    /// Watt-hours per mile, for display in the US.
    public var efficiencyWhPerMile: Double? {
        efficiencyKWhPerKm.map { $0 * 1000 * 1.609344 }
    }
}

public struct RideAnalyticsPeriod: Sendable, Hashable, Identifiable {
    public var id: String { rawType }
    public var rawType: String
    public var period: AnalyticsPeriod?
    public var granularity: AnalyticsGranularity?
    public var buckets: [RideBucket]
    public var totals: RideTotals

    init?(json: JSONValue) {
        guard let type = json["type"]?.textValue else { return nil }
        rawType = type
        period = AnalyticsPeriod(rawValue: type)
        granularity = json["granularity"]?.textValue.flatMap(AnalyticsGranularity.init(rawValue:))
        buckets = json["buckets"]?.arrayValue?.map(RideBucket.init(json:)) ?? []
        totals = RideTotals(json: json["summary"] ?? .null)
    }
}

public struct RideAnalytics: Sendable, Hashable {
    public var bikeID: String?
    public var periods: [RideAnalyticsPeriod]

    /// `nil` when the response has no `periods` array.
    public init?(json: JSONValue) {
        guard let periods = AnalyticsParsing.periods(json, make: RideAnalyticsPeriod.init(json:)) else { return nil }
        self.periods = periods
        bikeID = json["bikeId"]?.textValue
    }

    public func period(_ period: AnalyticsPeriod) -> RideAnalyticsPeriod? {
        periods.first { $0.period == period }
    }
}

// MARK: Charging

public struct ChargingBucket: Sendable, Hashable, Identifiable {
    public var id: String { startText }
    public var startText: String
    public var start: Date?
    public var sessionCount: Int
    public var energyAddedKWh: Double
    public var energyLostKWh: Double
    public var batteryAddedPercent: Double

    init(json: JSONValue) {
        startText = json["bucketStart"]?.textValue ?? ""
        start = AnalyticsParsing.day(startText)
        sessionCount = json["sessionCount"]?.intValue ?? 0
        energyAddedKWh = json["energyAddedKwh"]?.doubleValue ?? 0
        energyLostKWh = json["energyLostKwh"]?.doubleValue ?? 0
        batteryAddedPercent = json["sumBatteryAddedPercent"]?.doubleValue ?? 0
    }
}

public struct ChargingTotals: Sendable, Hashable {
    public var sessionCount: Int
    public var energyAddedKWh: Double
    public var energyLostKWh: Double
    public var batteryAddedPercent: Double
    /// Seconds (1958 for a single session, about 33 minutes).
    public var chargeTimeSeconds: Double

    init(json: JSONValue) {
        sessionCount = json["sessionCount"]?.intValue ?? 0
        energyAddedKWh = json["energyAddedKwh"]?.doubleValue ?? 0
        energyLostKWh = json["energyLostKwh"]?.doubleValue ?? 0
        batteryAddedPercent = json["totalBatteryAddedPercent"]?.doubleValue ?? 0
        chargeTimeSeconds = json["totalChargeTime"]?.doubleValue ?? 0
    }
}

public struct ChargingAnalyticsPeriod: Sendable, Hashable, Identifiable {
    public var id: String { rawType }
    public var rawType: String
    public var period: AnalyticsPeriod?
    public var granularity: AnalyticsGranularity?
    public var buckets: [ChargingBucket]
    public var totals: ChargingTotals

    init?(json: JSONValue) {
        guard let type = json["type"]?.textValue else { return nil }
        rawType = type
        period = AnalyticsPeriod(rawValue: type)
        granularity = json["granularity"]?.textValue.flatMap(AnalyticsGranularity.init(rawValue:))
        buckets = json["buckets"]?.arrayValue?.map(ChargingBucket.init(json:)) ?? []
        totals = ChargingTotals(json: json["summary"] ?? .null)
    }
}

public struct ChargingAnalytics: Sendable, Hashable {
    public var bikeID: String?
    public var periods: [ChargingAnalyticsPeriod]

    public init?(json: JSONValue) {
        guard let periods = AnalyticsParsing.periods(json, make: ChargingAnalyticsPeriod.init(json:)) else { return nil }
        self.periods = periods
        bikeID = json["bikeId"]?.textValue
    }

    public func period(_ period: AnalyticsPeriod) -> ChargingAnalyticsPeriod? {
        periods.first { $0.period == period }
    }
}
