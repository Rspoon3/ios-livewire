import Foundation

// Models for `bikes/{id}/ride/analytics` and `bikes/{id}/charging/analytics`.
//
// Both answer with the same envelope: `{bikeId, vin, periods: [...]}`. There are four periods
// (`WEEK`, `MONTH`, `3M`, `6M`), each with a `granularity` (`DAY`, `WEEK` or `MONTH`), a list of
// `buckets` and one `summary`. The shapes were confirmed against a real account on 2026-11-25
// (see docs/api.md). They decode straight from the response.

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

enum AnalyticsDate {
    /// Bucket starts are plain dates (`2026-11-01`). They become midnight in the current calendar.
    static func day(_ text: String) -> Date? {
        let parts = text.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

// MARK: Rides

public struct RideBucket: Sendable, Hashable, Identifiable, Decodable {
    public var id: String { startText }
    /// `bucketStart`, a plain date such as `2026-11-01`.
    public let startText: String
    public let rideCount: Int
    public let batteryUsedPercent: Double
    /// Miles. The response gives no unit; miles is inferred (see docs/api.md).
    public let distanceMiles: Double
    /// kWh per kilometre (the field name says so). `nil` when the bucket has no rides.
    public let efficiencyKWhPerKm: Double?

    public var start: Date? { AnalyticsDate.day(startText) }

    private enum CodingKeys: String, CodingKey {
        case startText = "bucketStart"
        case rideCount
        case batteryUsedPercent = "sumBatteryUsedPercent"
        case distanceMiles = "totalDistance"
        case efficiencyKWhPerKm = "totalEfficiencykWhPerKm"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startText = try container.decode(String.self, forKey: .startText)
        rideCount = try container.decodeIfPresent(Int.self, forKey: .rideCount) ?? 0
        batteryUsedPercent = try container.decodeIfPresent(Double.self, forKey: .batteryUsedPercent) ?? 0
        distanceMiles = try container.decodeIfPresent(Double.self, forKey: .distanceMiles) ?? 0
        efficiencyKWhPerKm = try container.decodeIfPresent(Double.self, forKey: .efficiencyKWhPerKm)
    }
}

public struct RideTotals: Sendable, Hashable, Decodable {
    public let rideCount: Int
    public let batteryUsedPercent: Double
    public let distanceMiles: Double
    public let durationSeconds: Double
    public let efficiencyKWhPerKm: Double?

    /// Watt-hours per mile, for display in the US.
    public var efficiencyWhPerMile: Double? {
        efficiencyKWhPerKm.map { $0 * 1000 * 1.609344 }
    }

    private enum CodingKeys: String, CodingKey {
        case rideCount
        case batteryUsedPercent = "totalBatteryUsedPercent"
        case distanceMiles = "totalDistance"
        case durationSeconds = "totalDurationSeconds"
        case efficiencyKWhPerKm = "totalEfficiencykWhPerKm"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rideCount = try container.decodeIfPresent(Int.self, forKey: .rideCount) ?? 0
        batteryUsedPercent = try container.decodeIfPresent(Double.self, forKey: .batteryUsedPercent) ?? 0
        distanceMiles = try container.decodeIfPresent(Double.self, forKey: .distanceMiles) ?? 0
        durationSeconds = try container.decodeIfPresent(Double.self, forKey: .durationSeconds) ?? 0
        efficiencyKWhPerKm = try container.decodeIfPresent(Double.self, forKey: .efficiencyKWhPerKm)
    }
}

public struct RideAnalyticsPeriod: Sendable, Hashable, Identifiable, Decodable {
    public var id: String { type }
    /// `WEEK`, `MONTH`, `3M` or `6M`. Kept as sent so a new period is not lost.
    public let type: String
    public let granularity: String
    public let buckets: [RideBucket]
    public let totals: RideTotals

    public var period: AnalyticsPeriod? { AnalyticsPeriod(rawValue: type) }
    public var bucketSize: AnalyticsGranularity? { AnalyticsGranularity(rawValue: granularity) }

    private enum CodingKeys: String, CodingKey {
        case type, granularity, buckets
        case totals = "summary"
    }
}

public struct RideAnalytics: Sendable, Hashable, Decodable {
    public let bikeID: String?
    public let periods: [RideAnalyticsPeriod]

    public func period(_ period: AnalyticsPeriod) -> RideAnalyticsPeriod? {
        periods.first { $0.period == period }
    }

    private enum CodingKeys: String, CodingKey {
        case bikeID = "bikeId"
        case periods
    }
}

// MARK: Charging

public struct ChargingBucket: Sendable, Hashable, Identifiable, Decodable {
    public var id: String { startText }
    public let startText: String
    public let sessionCount: Int
    public let energyAddedKWh: Double
    public let energyLostKWh: Double
    public let batteryAddedPercent: Double

    public var start: Date? { AnalyticsDate.day(startText) }

    private enum CodingKeys: String, CodingKey {
        case startText = "bucketStart"
        case sessionCount
        case energyAddedKWh = "energyAddedKwh"
        case energyLostKWh = "energyLostKwh"
        case batteryAddedPercent = "sumBatteryAddedPercent"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startText = try container.decode(String.self, forKey: .startText)
        sessionCount = try container.decodeIfPresent(Int.self, forKey: .sessionCount) ?? 0
        energyAddedKWh = try container.decodeIfPresent(Double.self, forKey: .energyAddedKWh) ?? 0
        energyLostKWh = try container.decodeIfPresent(Double.self, forKey: .energyLostKWh) ?? 0
        batteryAddedPercent = try container.decodeIfPresent(Double.self, forKey: .batteryAddedPercent) ?? 0
    }
}

public struct ChargingTotals: Sendable, Hashable, Decodable {
    public let sessionCount: Int
    public let energyAddedKWh: Double
    public let energyLostKWh: Double
    public let batteryAddedPercent: Double
    /// Seconds (1958 for a single session, about 33 minutes).
    public let chargeTimeSeconds: Double

    private enum CodingKeys: String, CodingKey {
        case sessionCount
        case energyAddedKWh = "energyAddedKwh"
        case energyLostKWh = "energyLostKwh"
        case batteryAddedPercent = "totalBatteryAddedPercent"
        case chargeTimeSeconds = "totalChargeTime"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionCount = try container.decodeIfPresent(Int.self, forKey: .sessionCount) ?? 0
        energyAddedKWh = try container.decodeIfPresent(Double.self, forKey: .energyAddedKWh) ?? 0
        energyLostKWh = try container.decodeIfPresent(Double.self, forKey: .energyLostKWh) ?? 0
        batteryAddedPercent = try container.decodeIfPresent(Double.self, forKey: .batteryAddedPercent) ?? 0
        chargeTimeSeconds = try container.decodeIfPresent(Double.self, forKey: .chargeTimeSeconds) ?? 0
    }
}

public struct ChargingAnalyticsPeriod: Sendable, Hashable, Identifiable, Decodable {
    public var id: String { type }
    public let type: String
    public let granularity: String
    public let buckets: [ChargingBucket]
    public let totals: ChargingTotals

    public var period: AnalyticsPeriod? { AnalyticsPeriod(rawValue: type) }
    public var bucketSize: AnalyticsGranularity? { AnalyticsGranularity(rawValue: granularity) }

    private enum CodingKeys: String, CodingKey {
        case type, granularity, buckets
        case totals = "summary"
    }
}

public struct ChargingAnalytics: Sendable, Hashable, Decodable {
    public let bikeID: String?
    public let periods: [ChargingAnalyticsPeriod]

    public func period(_ period: AnalyticsPeriod) -> ChargingAnalyticsPeriod? {
        periods.first { $0.period == period }
    }

    private enum CodingKeys: String, CodingKey {
        case bikeID = "bikeId"
        case periods
    }
}
